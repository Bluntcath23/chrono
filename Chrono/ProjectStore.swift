//
//  ProjectStore.swift
//  Chrono
//
//  Created by Ivan Inozemtsev on 16.10.26.
//

import Foundation
import Combine

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
    static let checkpointInterval: TimeInterval = 30

    /// `~/Library/Application Support/Chrono/projects.json` (inside the sandbox container).
    nonisolated static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Chrono", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
    }

    private let storageURL: URL
    private let now: () -> Date
    private var runningSince: Date?
    private var lastCheckpoint: Date?
    private var tickTimer: Timer?

    init(storageURL: URL = ProjectStore.defaultStorageURL, now: @escaping () -> Date = Date.init) {
        self.storageURL = storageURL
        self.now = now
        self.tick = now()

        if let loaded = Self.load(from: storageURL) {
            var projects = loaded.projects
            let activeID = projects.contains(where: { $0.id == loaded.activeProjectID })
                ? loaded.activeProjectID
                : projects[0].id
            // Unclean exit while running: credit up to the last checkpoint, come back paused.
            if let since = loaded.runningSince,
               let index = projects.firstIndex(where: { $0.id == activeID }) {
                let checkpoint = loaded.lastCheckpoint ?? since
                projects[index].accumulated += max(0, checkpoint.timeIntervalSince(since))
            }
            self.projects = projects
            self.activeProjectID = activeID
            if loaded.runningSince != nil { save() }
        } else {
            let seed = Project(name: Self.defaultProjectName, createdAt: now())
            self.projects = [seed]
            self.activeProjectID = seed.id
            save()
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

    func start() {
        guard !isRunning else { return }
        let date = now()
        runningSince = date
        lastCheckpoint = date
        isRunning = true
        tick = date
        startTickTimer()
        save()
    }

    /// Credits time up to now.
    func stop() {
        stop(creditingUntil: now())
    }

    /// Credits only up to `date` (clamped to `[runningSince, now]`). Used by
    /// auto-pause so idle time is dropped.
    func stop(creditingUntil date: Date) {
        guard isRunning, let since = runningSince else { return }
        let end = max(since, min(date, now()))
        if let index = index(of: activeProjectID) {
            projects[index].accumulated += end.timeIntervalSince(since)
        }
        endRunningState()
        save()
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    /// Matches v1 Reset semantics: reset STOPS the timer and zeroes the active
    /// project. (Unlike `resetTime(for:)`, which keeps a running timer going.)
    func resetActive() {
        if isRunning { endRunningState() }   // live segment is discarded
        if let index = index(of: activeProjectID) {
            projects[index].accumulated = 0
        }
        save()
    }

    /// Zeroes a project's time. If the timer is running on that project it
    /// keeps running, restarting from 0.
    func resetTime(for id: UUID) {
        guard let index = index(of: id) else { return }
        projects[index].accumulated = 0
        if isRunning, id == activeProjectID {
            let date = now()
            runningSince = date
            lastCheckpoint = date
            tick = date
        }
        save()
    }

    /// Makes `id` active. If the timer is running (on the previous project) it
    /// is stopped and credited; the new project starts paused. Selecting the
    /// already-active project is a no-op.
    func select(_ id: UUID) {
        guard id != activeProjectID, index(of: id) != nil else { return }
        if isRunning { stop() }
        activeProjectID = id
        save()
    }

    func switchAndStart(_ id: UUID) {
        guard index(of: id) != nil else { return }
        select(id)
        start()
    }

    /// 0-based; out of range = no-op.
    func switchAndStart(index: Int) {
        guard projects.indices.contains(index) else { return }
        switchAndStart(projects[index].id)
    }

    // MARK: - Editing

    /// Trimmed; empty → nil. Appended at the end; does NOT change the active project.
    @discardableResult func addProject(named name: String) -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = Project(name: trimmed, createdAt: now())
        projects.append(project)
        save()
        return project
    }

    /// Trimmed; empty → ignored.
    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = index(of: id), projects[index].name != trimmed else { return }
        projects[index].name = trimmed
        save()
    }

    /// No-op when `!canDelete`. Deleting the active project stops the timer
    /// (its live segment is discarded along with the project) and activates
    /// the project above it, or the next one if it was first.
    func delete(_ id: UUID) {
        guard canDelete, let index = index(of: id) else { return }
        if id == activeProjectID {
            if isRunning { endRunningState() }
            let neighbor = index > 0 ? projects[index - 1] : projects[index + 1]
            activeProjectID = neighbor.id
        }
        projects.remove(at: index)
        save()
    }

    /// Synchronous save (call on terminate). A running timer keeps running;
    /// its state is checkpointed so a relaunch credits time up to now.
    func flush() {
        if isRunning { lastCheckpoint = now() }
        save()
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
            save()
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

    private struct Snapshot: Codable {
        var version: Int = 1
        var projects: [Project]
        var activeProjectID: UUID
        var runningSince: Date?
        var lastCheckpoint: Date?
    }

    private static func load(from url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            guard !snapshot.projects.isEmpty else { return nil }
            return snapshot
        } catch {
            // Keep the unreadable file around instead of silently overwriting it.
            let backup = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            print("ProjectStore: could not decode \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func save() {
        let snapshot = Snapshot(
            projects: projects,
            activeProjectID: activeProjectID,
            runningSince: runningSince,
            lastCheckpoint: lastCheckpoint
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("ProjectStore: save failed: \(error)")
        }
    }
}
