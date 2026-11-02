//
//  ProjectStore.swift
//  Chrono
//
//  Created by Ivan Inozemtsev on 16.10.26.
//

import Foundation
import Combine
import os

/// Single source of truth for projects and the (single) running timer.
///
/// Timing is wall-clock based: the live segment is `now - runningSince`. The
/// 0.1 s timer only bumps `tick` so SwiftUI refreshes; it never sums time.
@MainActor final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project]
    @Published private(set) var activeProjectID: UUID
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var tick: Date          // updated every 0.1 s while running; drives UI refresh

    static let defaultProjectName = "My Project"
    /// Every mutation is logged with its `source` (the UI control, hotkey or
    /// system event that caused it), the project's short id and the seconds
    /// involved; names stay private:
    /// `log show --predicate 'subsystem == "com.inozemtsev.Chrono"' --info --last 2d`.
    private static let log = Logger(subsystem: "com.inozemtsev.Chrono", category: "Store")
    /// How often a running timer is checkpointed to disk. After an unclean exit
    /// (crash, force quit, Xcode stop) the relaunch credits time up to the last
    /// checkpoint, so at most this many seconds are lost.
    static let checkpointInterval: TimeInterval = 10

    /// `~/Library/Application Support/Chrono/projects.json` (inside the sandbox container).
    nonisolated static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Chrono", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
    }

    let storageURL: URL
    private let now: () -> Date
    private var runningSince: Date?
    /// When the current running segment started; `nil` while paused.
    var runningStart: Date? { runningSince }
    private var lastCheckpoint: Date?
    private var tickTimer: Timer?
    /// Set when a file exists on disk but could neither be loaded nor backed up:
    /// nothing is written this session, so the user's file is never replaced.
    private(set) var isPersistenceDisabled = false

    init(storageURL: URL = ProjectStore.defaultStorageURL, now: @escaping () -> Date = Date.init) {
        self.storageURL = storageURL
        self.now = now
        self.tick = now()

        let outcome = ProjectPersistence.load(from: storageURL)
        Self.log.notice("load file=\(storageURL.path, privacy: .public) outcome=\(outcome.summary, privacy: .public)")

        switch outcome {
        case .loaded(let loaded):
            var projects = loaded.projects
            let activeID = loaded.activeProjectID.flatMap { id in
                projects.contains(where: { $0.id == id }) ? id : nil
            } ?? projects[0].id
            // Unclean exit while running: credit up to the last checkpoint, come back paused.
            if let since = loaded.runningSince,
               let index = projects.firstIndex(where: { $0.id == activeID }) {
                let credited = ProjectPersistence.recoveredSegment(
                    runningSince: since, lastCheckpoint: loaded.lastCheckpoint, now: now()
                )
                projects[index].accumulated += credited
                Self.log.notice("recover [load] project=\(Self.tag(projects[index]), privacy: .public) credited=\(credited, privacy: .public)s, now paused")
            }
            self.projects = projects
            self.activeProjectID = activeID
            Self.log.notice("loaded \(projects.count, privacy: .public) projects: \(Self.describe(projects), privacy: .public) active=\(activeID.uuidString.prefix(8), privacy: .public)")
            if loaded.runningSince != nil { save(reason: "recovery") }

        case .missing:
            let seed = Project(name: Self.defaultProjectName, createdAt: now())
            self.projects = [seed]
            self.activeProjectID = seed.id
            Self.log.notice("no projects file yet; seeding \(Self.tag(seed), privacy: .public)")
            save(reason: "first launch seed")

        case .failed(let reason):
            // Never overwrite a file that couldn't be loaded: keep a copy first.
            // If even the copy fails, don't save at all this session.
            let seed = Project(name: Self.defaultProjectName, createdAt: now())
            self.projects = [seed]
            self.activeProjectID = seed.id
            if let backup = ProjectPersistence.backUp(storageURL, now: now()) {
                Self.log.fault("could not load projects (\(reason, privacy: .public)); kept the original as \(backup.lastPathComponent, privacy: .public), seeding a new list")
                save(reason: "seed after failed load")
            } else {
                isPersistenceDisabled = true
                Self.log.fault("could not load projects (\(reason, privacy: .public)) and could not back the file up; saving is DISABLED this session so the file is not overwritten")
            }
        }
    }

    // MARK: - Queries

    var activeProject: Project {
        projects.first(where: { $0.id == activeProjectID }) ?? projects[0]
    }

    /// Includes the live segment.
    var activeElapsed: TimeInterval { elapsed(for: activeProjectID) }

    /// All projects, includes the live segment.
    var totalElapsed: TimeInterval {
        projects.reduce(0) { $0 + $1.accumulated } + liveSegment
    }

    var canDelete: Bool { projects.count > 1 }

    func elapsed(for id: UUID) -> TimeInterval {
        guard let project = projects.first(where: { $0.id == id }) else { return 0 }
        return project.accumulated + (id == activeProjectID ? liveSegment : 0)
    }

    func index(of id: UUID) -> Int? {
        projects.firstIndex(where: { $0.id == id })
    }

    private var liveSegment: TimeInterval {
        guard let since = runningSince else { return 0 }
        return max(0, now().timeIntervalSince(since))
    }

    // MARK: - Timer control

    func start(source: String = "unspecified") {
        guard !isRunning else { return }
        Self.log.notice("start [\(source, privacy: .public)] project=\(Self.tag(self.activeProject), privacy: .public) accumulated=\(self.activeProject.accumulated, privacy: .public)s")
        let date = now()
        runningSince = date
        lastCheckpoint = date
        isRunning = true
        tick = date
        startTickTimer()
        save(reason: "start")
    }

    /// Credits time up to now.
    func stop(source: String = "unspecified") {
        stop(creditingUntil: now(), source: source)
    }

    /// Credits only up to `date` (clamped to `[runningSince, now]`). Used by
    /// the idle auto-pause so time after the idle threshold isn't counted.
    func stop(creditingUntil date: Date, source: String = "unspecified") {
        guard isRunning, let since = runningSince else { return }
        let end = max(since, min(date, now()))
        Self.log.notice("stop [\(source, privacy: .public)] project=\(Self.tag(self.activeProject), privacy: .public) segment=\(end.timeIntervalSince(since), privacy: .public)s creditedUntil=\(end.timeIntervalSince1970, privacy: .public) now=\(self.now().timeIntervalSince1970, privacy: .public)")
        if let index = index(of: activeProjectID) {
            projects[index].accumulated += end.timeIntervalSince(since)
        }
        endRunningState()
        save(reason: "stop")
    }

    func toggle(source: String = "unspecified") {
        isRunning ? stop(source: "toggle←" + source) : start(source: "toggle←" + source)
    }

    /// Matches v1 Reset semantics: reset STOPS the timer and zeroes the active
    /// project. (Unlike `resetTime(for:)`, which keeps a running timer going.)
    func resetActive(source: String = "unspecified") {
        Self.log.notice("resetActive [\(source, privacy: .public)] project=\(Self.tag(self.activeProject), privacy: .public) discarded=\(self.activeElapsed, privacy: .public)s")
        if isRunning { endRunningState() }   // live segment is discarded
        if let index = index(of: activeProjectID) {
            projects[index].accumulated = 0
        }
        save(reason: "resetActive")
    }

    /// Zeroes a project's time. If the timer is running on that project it
    /// keeps running, restarting from 0.
    func resetTime(for id: UUID, source: String = "unspecified") {
        guard let index = index(of: id) else { return }
        Self.log.notice("resetTime [\(source, privacy: .public)] project=\(Self.tag(self.projects[index]), privacy: .public) discarded=\(self.elapsed(for: id), privacy: .public)s")
        projects[index].accumulated = 0
        if isRunning, id == activeProjectID {
            let date = now()
            runningSince = date
            lastCheckpoint = date
            tick = date
        }
        save(reason: "resetTime")
    }

    /// Makes `id` active. If the timer is running (on the previous project) it
    /// is stopped and credited; the new project starts paused. Selecting the
    /// already-active project is a no-op.
    func select(_ id: UUID, source: String = "unspecified") {
        guard id != activeProjectID, let index = index(of: id) else { return }
        Self.log.notice("select [\(source, privacy: .public)] \(Self.tag(self.activeProject), privacy: .public) → \(Self.tag(self.projects[index]), privacy: .public)")
        if isRunning { stop(source: "select←" + source) }
        activeProjectID = id
        save(reason: "select")
    }

    func switchAndStart(_ id: UUID, source: String = "unspecified") {
        guard let index = index(of: id) else { return }
        Self.log.notice("switchAndStart [\(source, privacy: .public)] → \(Self.tag(self.projects[index]), privacy: .public)")
        select(id, source: "switchAndStart←" + source)
        start(source: "switchAndStart←" + source)
    }

    /// 0-based; out of range = no-op.
    func switchAndStart(index: Int, source: String = "unspecified") {
        guard projects.indices.contains(index) else { return }
        switchAndStart(projects[index].id, source: "index \(index)←" + source)
    }

    // MARK: - Editing

    /// Trimmed; empty → nil. Appended at the end; does NOT change the active project.
    @discardableResult func addProject(named name: String, source: String = "unspecified") -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = Project(name: trimmed, createdAt: now())
        projects.append(project)
        Self.log.notice("add [\(source, privacy: .public)] project=\(Self.tag(project), privacy: .public) name=\(trimmed, privacy: .private)")
        save(reason: "add")
        return project
    }

    /// Trimmed; empty → ignored.
    func rename(_ id: UUID, to name: String, source: String = "unspecified") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = index(of: id), projects[index].name != trimmed else { return }
        Self.log.notice("rename [\(source, privacy: .public)] project=\(Self.tag(self.projects[index]), privacy: .public) \(self.projects[index].name, privacy: .private) → \(trimmed, privacy: .private)")
        projects[index].name = trimmed
        save(reason: "rename")
    }

    /// No-op when `!canDelete`. Deleting the active project stops the timer
    /// (its live segment is discarded along with the project) and activates
    /// the project above it, or the next one if it was first.
    func delete(_ id: UUID, source: String = "unspecified") {
        guard canDelete, let index = index(of: id) else { return }
        Self.log.notice("delete [\(source, privacy: .public)] project=\(Self.tag(self.projects[index]), privacy: .public) discarded=\(self.elapsed(for: id), privacy: .public)s wasActive=\(id == self.activeProjectID, privacy: .public)")
        if id == activeProjectID {
            if isRunning { endRunningState() }
            let neighbor = index > 0 ? projects[index - 1] : projects[index + 1]
            activeProjectID = neighbor.id
        }
        projects.remove(at: index)
        save(reason: "delete")
    }

    /// Synchronous save (call on terminate). A running timer keeps running;
    /// its state is checkpointed so a relaunch credits time up to now.
    func flush(source: String = "unspecified") {
        Self.log.notice("flush [\(source, privacy: .public)] running=\(self.isRunning, privacy: .public)")
        if isRunning { lastCheckpoint = now() }
        save(reason: "flush←" + source)
    }

    // MARK: - Ticking

    private func startTickTimer() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.handleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func handleTick() {
        let date = now()
        tick = date
        if let last = lastCheckpoint, date.timeIntervalSince(last) >= Self.checkpointInterval {
            lastCheckpoint = date
            save(reason: "checkpoint")
        }
    }

    /// Clears running state without crediting anything.
    private func endRunningState() {
        tickTimer?.invalidate()
        tickTimer = nil
        runningSince = nil
        lastCheckpoint = nil
        isRunning = false
        tick = now()
    }

    // MARK: - Persistence

    private func save(reason: String) {
        guard !isPersistenceDisabled else {
            Self.log.error("save skipped (\(reason, privacy: .public)): saving is disabled after a failed load")
            return
        }
        let snapshot = ProjectPersistence.Snapshot(
            projects: projects,
            activeProjectID: activeProjectID,
            runningSince: runningSince,
            lastCheckpoint: lastCheckpoint
        )
        do {
            try ProjectPersistence.write(snapshot, to: storageURL)
            Self.log.debug("saved (\(reason, privacy: .public)): \(Self.describe(self.projects), privacy: .public)")
        } catch {
            Self.log.error("save failed (\(reason, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Log-safe project identifier: the first 8 characters of its UUID (names stay private).
    private static func tag(_ project: Project) -> String {
        String(project.id.uuidString.prefix(8))
    }

    private static func describe(_ projects: [Project]) -> String {
        projects.map { "\(tag($0))=\(Int($0.accumulated))s" }.joined(separator: ", ")
    }
}

// MARK: - File format

/// Reading and writing `projects.json`. Pure and `nonisolated`, so it can be
/// tested without the store.
///
/// Decoding is lenient and backward-compatible: everything except the project
/// list may be missing (see also `Project.init(from:)`), and unknown keys are
/// ignored, so files from older and newer builds both load.
nonisolated enum ProjectPersistence {
    struct Snapshot: Codable, Equatable {
        var version: Int = 1
        var projects: [Project]
        var activeProjectID: UUID?
        var runningSince: Date?
        var lastCheckpoint: Date?

        init(version: Int = 1, projects: [Project], activeProjectID: UUID?, runningSince: Date?, lastCheckpoint: Date?) {
            self.version = version
            self.projects = projects
            self.activeProjectID = activeProjectID
            self.runningSince = runningSince
            self.lastCheckpoint = lastCheckpoint
        }

        private enum CodingKeys: String, CodingKey {
            case version, projects, activeProjectID, runningSince, lastCheckpoint
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? 1
            projects = try container.decode([Project].self, forKey: .projects)
            activeProjectID = (try? container.decodeIfPresent(UUID.self, forKey: .activeProjectID)) ?? nil
            runningSince = (try? container.decodeIfPresent(Date.self, forKey: .runningSince)) ?? nil
            lastCheckpoint = (try? container.decodeIfPresent(Date.self, forKey: .lastCheckpoint)) ?? nil
        }
    }

    enum LoadOutcome: Equatable {
        /// No file yet (fresh install).
        case missing
        case loaded(Snapshot)
        /// A file exists but couldn't be read or decoded, or holds no projects.
        case failed(String)

        var summary: String {
            switch self {
            case .missing:
                return "missing"
            case .loaded(let snapshot):
                return "loaded v\(snapshot.version), \(snapshot.projects.count) projects, running=\(snapshot.runningSince != nil)"
            case .failed(let reason):
                return "FAILED: \(reason)"
            }
        }
    }

    static func load(from url: URL) -> LoadOutcome {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) { return .missing }
            return .failed("read error: \(error.localizedDescription)")
        }
        return decode(data)
    }

    static func decode(_ data: Data) -> LoadOutcome {
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            guard !snapshot.projects.isEmpty else { return .failed("file has no projects") }
            return .loaded(snapshot)
        } catch {
            return .failed("decode error: \(error)")
        }
    }

    static func encode(_ snapshot: Snapshot) throws -> Data {
        var snapshot = snapshot
        for index in snapshot.projects.indices {
            snapshot.projects[index].accumulated = Project.sanitized(snapshot.projects[index].accumulated)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// Atomic: a reader (or a crash mid-write) never sees a half-written file.
    static func write(_ snapshot: Snapshot, to url: URL) throws {
        let data = try encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Copies `url` to `projects.json.<timestamp>.bak` next to it, never
    /// replacing an earlier backup. Returns nil if the copy failed.
    static func backUp(_ url: URL, now: Date) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now)
        let directory = url.deletingLastPathComponent()
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt)"
            let backup = directory.appendingPathComponent("\(url.lastPathComponent).\(stamp)\(suffix).bak")
            if FileManager.default.fileExists(atPath: backup.path) { continue }
            do {
                try FileManager.default.copyItem(at: url, to: backup)
                return backup
            } catch {
                return nil
            }
        }
        return nil
    }

    /// Time to credit for a segment that was still running when the app last
    /// exited: up to the last checkpoint, never negative, never past `now`
    /// (guards against clock changes).
    static func recoveredSegment(runningSince: Date, lastCheckpoint: Date?, now: Date) -> TimeInterval {
        let end = min(lastCheckpoint ?? runningSince, now)
        let segment = end.timeIntervalSince(runningSince)
        guard segment.isFinite, segment > 0 else { return 0 }
        return segment
    }
}
