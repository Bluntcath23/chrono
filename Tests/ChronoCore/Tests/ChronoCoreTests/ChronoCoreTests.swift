import XCTest
@testable import ChronoCore

/// A controllable clock for `ProjectStore(now:)`.
@MainActor final class TestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
    var now: () -> Date { { [unowned self] in self.date } }
}

@MainActor class StoreTestCase: XCTestCase {
    var directory: URL!
    var fileURL: URL!
    var clock: TestClock!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chrono-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("projects.json")
        clock = TestClock()
    }

    override func tearDown() async throws {
        if let fileURL {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        }
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    /// Stores are never released, like in the app. With default MainActor
    /// isolation their deinit is isolated, and releasing one inside an XCTest
    /// method aborts in the Swift runtime (`swift_task_deinitOnExecutorImpl`
    /// → `TaskLocal::StopLookupScope`, "pointer being freed was not allocated").
    static var retained: [AnyObject] = []

    func makeStore() -> ProjectStore {
        let store = ProjectStore(storageURL: fileURL, now: clock.now)
        Self.retained.append(store)
        return store
    }

    func backups() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "bak" }
    }

    func writeRaw(_ json: String) throws {
        try Data(json.utf8).write(to: fileURL)
    }
}

// MARK: - Persistence

@MainActor final class PersistenceTests: StoreTestCase {
    func testMissingFileSeedsDefaultProjectAndSaves() throws {
        let store = makeStore()
        XCTAssertEqual(store.projects.map(\.name), [ProjectStore.defaultProjectName])
        XCTAssertEqual(store.activeElapsed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(try backups().isEmpty)
    }

    func testRoundTripKeepsNamesTimesAndActiveProject() throws {
        let store = makeStore()
        store.rename(store.activeProjectID, to: "Client Website", source: "test")
        let second = try XCTUnwrap(store.addProject(named: "Branding", source: "test"))
        store.start(source: "test")
        clock.advance(3000)
        store.stop(source: "test")
        store.select(second.id, source: "test")

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.projects.map(\.name), ["Client Website", "Branding"])
        XCTAssertEqual(reloaded.projects[0].accumulated, 3000, accuracy: 0.001)
        XCTAssertEqual(reloaded.activeProjectID, second.id)
        XCTAssertFalse(reloaded.isRunning)
    }

    func testCorruptFileIsBackedUpBeforeAnythingIsWritten() throws {
        let garbage = "{ \"projects\": [ { \"id\": \"not-a-uuid\" "
        try writeRaw(garbage)

        let store = makeStore()
        XCTAssertEqual(store.projects.map(\.name), [ProjectStore.defaultProjectName])
        XCTAssertFalse(store.isPersistenceDisabled)

        let backup = try XCTUnwrap(try backups().first)
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("projects.json."))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), garbage, "original bytes must survive")
    }

    func testRepeatedFailedLoadsNeverReplaceAnEarlierBackup() throws {
        try writeRaw("first broken file")
        _ = makeStore()
        try writeRaw("second broken file")
        _ = makeStore()   // same clock second → needs a distinct backup name
        let contents = try backups().map { try String(contentsOf: $0, encoding: .utf8) }.sorted()
        XCTAssertEqual(contents, ["first broken file", "second broken file"])
    }

    func testEmptyProjectListIsBackedUpNotSilentlyReplaced() throws {
        try writeRaw(#"{"version":1,"projects":[],"activeProjectID":"7B1C1F7E-4D35-4B3C-9D8B-2C9C7B6E5A10"}"#)
        _ = makeStore()
        XCTAssertEqual(try backups().count, 1)
    }

    func testUnreadableFileIsNeverOverwritten() throws {
        let original = #"{"version":1,"projects":[{"id":"7B1C1F7E-4D35-4B3C-9D8B-2C9C7B6E5A10","name":"Precious","accumulated":4080,"createdAt":0}],"activeProjectID":"7B1C1F7E-4D35-4B3C-9D8B-2C9C7B6E5A10"}"#
        try writeRaw(original)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: fileURL.path), "running as root; can't make the file unreadable")

        let store = makeStore()
        XCTAssertTrue(store.isPersistenceDisabled)
        // Mutations must not touch the file.
        store.addProject(named: "New", source: "test")
        store.start(source: "test")
        clock.advance(60)
        store.flush(source: "test")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), original)
    }

    func testLegacyAndMinimalFilesDecode() throws {
        // No version, no activeProjectID, missing / blank / invalid fields.
        try writeRaw("""
        {"projects":[
          {"id":"7B1C1F7E-4D35-4B3C-9D8B-2C9C7B6E5A10","name":"Old","accumulated":120},
          {"id":"8B1C1F7E-4D35-4B3C-9D8B-2C9C7B6E5A11","name":"   ","accumulated":-5,"createdAt":0},
          {"id":"9B1C1F7E-4D35-4B3C-9D8B-2C9C7B6E5A12"}
        ]}
        """)
        let store = makeStore()
        XCTAssertEqual(store.projects.map(\.name), ["Old", Project.fallbackName, Project.fallbackName])
        XCTAssertEqual(store.projects.map(\.accumulated), [120, 0, 0])
        XCTAssertEqual(store.activeProjectID, store.projects[0].id)
        XCTAssertTrue(try backups().isEmpty)
    }

    func testUnknownKeysFromNewerBuildsAreIgnored() throws {
        try writeRaw("""
        {"version":7,"futureFlag":true,"projects":[
          {"id":"7B1C1F7E-4D35-4B3C-9D8B-2C9C7B6E5A10","name":"Kept","accumulated":61,"createdAt":0,"color":"blue"}
        ],"activeProjectID":"7B1C1F7E-4D35-4B3C-9D8B-2C9C7B6E5A10"}
        """)
        let store = makeStore()
        XCTAssertEqual(store.projects.map(\.name), ["Kept"])
        XCTAssertEqual(store.activeElapsed, 61)
    }

    /// 2.0.0 decoded with synthesized Codable (every key required). Files
    /// written by this build must still contain all of them, so a downgrade
    /// can read them.
    func testWrittenFileKeepsEveryKeyTheOldDecoderRequired() throws {
        let store = makeStore()
        store.start(source: "test")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        for key in ["version", "projects", "activeProjectID", "runningSince", "lastCheckpoint"] {
            XCTAssertNotNil(object[key], key)
        }
        let project = try XCTUnwrap((object["projects"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(project.keys), ["id", "name", "accumulated", "createdAt"])
    }

    func testEncodeSanitizesNonFiniteTime() throws {
        let snapshot = ProjectPersistence.Snapshot(
            projects: [Project(name: "X", accumulated: .nan)],
            activeProjectID: nil, runningSince: nil, lastCheckpoint: nil
        )
        let data = try ProjectPersistence.encode(snapshot)   // would throw on NaN
        guard case .loaded(let decoded) = ProjectPersistence.decode(data) else { return XCTFail("decode failed") }
        XCTAssertEqual(decoded.projects[0].accumulated, 0)
    }
}

// MARK: - Restart / recovery / time math

@MainActor final class TimingTests: StoreTestCase {
    func testUncleanExitCreditsUpToLastCheckpointAndComesBackPaused() throws {
        let id = UUID()
        let since = clock.date
        let snapshot = ProjectPersistence.Snapshot(
            projects: [Project(id: id, name: "P", accumulated: 100)],
            activeProjectID: id,
            runningSince: since,
            lastCheckpoint: since.addingTimeInterval(3000)
        )
        try ProjectPersistence.write(snapshot, to: fileURL)
        clock.advance(3020)   // died 20 s after the last checkpoint

        let store = makeStore()
        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(store.activeElapsed, 3100, accuracy: 0.001)

        // Recovery was persisted (not credited twice on the next launch).
        let again = makeStore()
        XCTAssertEqual(again.activeElapsed, 3100, accuracy: 0.001)
    }

    func testRecoveryNeverGoesNegativeOrPastNow() {
        let since = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(ProjectPersistence.recoveredSegment(runningSince: since, lastCheckpoint: since.addingTimeInterval(-50), now: since), 0)
        XCTAssertEqual(ProjectPersistence.recoveredSegment(runningSince: since, lastCheckpoint: nil, now: since.addingTimeInterval(99)), 0)
        // Clock moved backwards since the checkpoint: credit only up to now.
        XCTAssertEqual(ProjectPersistence.recoveredSegment(runningSince: since, lastCheckpoint: since.addingTimeInterval(500), now: since.addingTimeInterval(200)), 200)
    }

    func testCheckpointIntervalBoundsLossAfterACrash() {
        XCTAssertLessThanOrEqual(ProjectStore.checkpointInterval, 10)
    }

    /// The reported flow: ~50 min, restart, keep going to ~1h08m.
    func testRestartMidSessionNeitherResetsNorDoubleCounts() throws {
        let store = makeStore()
        store.rename(store.activeProjectID, to: "Named", source: "test")
        store.start(source: "test")
        clock.advance(50 * 60)
        store.flush(source: "quit")   // applicationWillTerminate

        let relaunched = makeStore()
        XCTAssertEqual(relaunched.activeElapsed, 50 * 60, accuracy: 0.001)
        relaunched.start(source: "test")
        clock.advance(18 * 60)
        XCTAssertEqual(relaunched.activeElapsed, 68 * 60, accuracy: 0.001)
        XCTAssertEqual(TimeFormat.clock(relaunched.activeElapsed), "1:08:00")
        relaunched.stop(source: "test")
        relaunched.start(source: "test")
        clock.advance(30)
        relaunched.stop(source: "test")

        let third = makeStore()
        XCTAssertEqual(third.activeProject.name, "Named")
        XCTAssertEqual(third.activeElapsed, 68 * 60 + 30, accuracy: 0.001)
    }

    func testStopCreditingUntilIsClampedToTheSegment() {
        let store = makeStore()
        store.start(source: "test")
        let start = clock.date
        clock.advance(600)
        store.stop(creditingUntil: start.addingTimeInterval(-100), source: "test")
        XCTAssertEqual(store.activeElapsed, 0)

        store.start(source: "test")
        clock.advance(100)
        store.stop(creditingUntil: clock.date.addingTimeInterval(1000), source: "test")
        XCTAssertEqual(store.activeElapsed, 100, accuracy: 0.001)
    }

    /// Mirrors `MenuBarManager.setupAutoPause`: credit up to lastInput + threshold.
    func testIdleAutoPauseCountsExactlyTheThreshold() {
        let store = makeStore()
        store.start(source: "test")
        let lastInput = clock.date.addingTimeInterval(120)
        clock.advance(120 + 300 + 45)   // the check ran 45 s late
        let idleStart = max(lastInput, store.runningStart ?? lastInput)
        store.stop(creditingUntil: idleStart.addingTimeInterval(300), source: "test")
        XCTAssertEqual(store.activeElapsed, 420, accuracy: 0.001)
    }

    func testResetKeepsTheNameAndOnlyZeroesTime() {
        let store = makeStore()
        store.rename(store.activeProjectID, to: "Named", source: "test")
        store.start(source: "test")
        clock.advance(4000)
        store.resetActive(source: "test")
        XCTAssertEqual(store.activeProject.name, "Named")
        XCTAssertEqual(store.activeElapsed, 0)
        XCTAssertFalse(store.isRunning)
    }

    func testBlankNamesAreNeverSaved() {
        let store = makeStore()
        store.rename(store.activeProjectID, to: "Named", source: "test")
        store.rename(store.activeProjectID, to: "   \n", source: "test")
        XCTAssertEqual(store.activeProject.name, "Named")
        XCTAssertNil(store.addProject(named: " \t ", source: "test"))
        XCTAssertEqual(store.projects.count, 1)
    }
}

// MARK: - Formatting

final class TimeFormatTests: XCTestCase {
    func testClockBoundaryAndTruncation() {
        XCTAssertEqual(TimeFormat.clock(0), "00:00.0")
        XCTAssertEqual(TimeFormat.clock(3599.95), "59:59.9")
        XCTAssertEqual(TimeFormat.clock(3599.99999), "59:59.9")
        XCTAssertEqual(TimeFormat.clock(3600), "1:00:00")
        XCTAssertEqual(TimeFormat.clock(4080.9), "1:08:00")
        XCTAssertEqual(TimeFormat.clock(-5), "00:00.0")
        XCTAssertEqual(TimeFormat.clock(.nan), "00:00.0")
        XCTAssertEqual(TimeFormat.clock(.infinity), "00:00.0")
    }

    func testDuration() {
        XCTAssertEqual(TimeFormat.duration(59), "0h 00m")
        XCTAssertEqual(TimeFormat.duration(4080), "1h 08m")
    }
}

// MARK: - Idle detection

@MainActor final class ActivityMonitorTests: XCTestCase {
    final class Probe {
        var idle: TimeInterval = 299
        var fired: [Date] = []
    }

    /// Kept alive for the whole test run, like in the app (see `StoreTestCase.retained`).
    static var monitors: [ActivityMonitor] = []

    func testFiresOnceAtThresholdAndRearmsAfterActivity() {
        let probe = Probe()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let monitor = ActivityMonitor(threshold: 300, idleSeconds: { probe.idle }, now: { now })
        Self.monitors.append(monitor)
        monitor.onInactivityDetected = { probe.fired.append($0) }
        monitor.startMonitoring()
        defer { monitor.stopMonitoring() }
        XCTAssertTrue(probe.fired.isEmpty)

        probe.idle = 300
        monitor.check()
        XCTAssertEqual(probe.fired, [now.addingTimeInterval(-300)])
        probe.idle = 330
        monitor.check()
        XCTAssertEqual(probe.fired.count, 1, "fires once per idle period")

        probe.idle = 1
        monitor.check()
        probe.idle = 301
        monitor.check()
        XCTAssertEqual(probe.fired.count, 2)
    }
}

// MARK: - Status item toggle

final class StatusItemClickTrackerTests: XCTestCase {
    func testClickWhileOpenCloses() {
        var tracker = StatusItemClickTracker()
        tracker.mouseDown(at: 100, panelVisible: true)
        XCTAssertTrue(tracker.clickClosesPanel(mouseUpAt: 100.1, panelVisible: true))
    }

    /// The bug: something hides the panel on mouse-down, then the mouse-up
    /// action saw a hidden panel and reopened it.
    func testHiddenDuringTheClickStaysClosed() {
        var tracker = StatusItemClickTracker()
        tracker.mouseDown(at: 100, panelVisible: true)
        tracker.panelHiddenExternally(at: 100.01)
        XCTAssertTrue(tracker.clickClosesPanel(mouseUpAt: 100.1, panelVisible: false))
    }

    func testHiddenJustBeforeTheMouseDownWasSeenStaysClosed() {
        var tracker = StatusItemClickTracker()
        tracker.panelHiddenExternally(at: 100.002)   // hide ran before the local monitor
        tracker.mouseDown(at: 100.0, panelVisible: false)
        XCTAssertTrue(tracker.clickClosesPanel(mouseUpAt: 100.1, panelVisible: false))
    }

    func testClickWhileClosedOpens() {
        var tracker = StatusItemClickTracker()
        tracker.panelHiddenExternally(at: 50)   // closed by an outside click long ago
        tracker.mouseDown(at: 100, panelVisible: false)
        XCTAssertFalse(tracker.clickClosesPanel(mouseUpAt: 100.1, panelVisible: false))
    }

    func testFallbackWithoutMouseDown() {
        var tracker = StatusItemClickTracker()
        tracker.panelHiddenExternally(at: 99.9)
        XCTAssertTrue(tracker.clickClosesPanel(mouseUpAt: 100, panelVisible: false))
        var later = StatusItemClickTracker()
        later.panelHiddenExternally(at: 98)
        XCTAssertFalse(later.clickClosesPanel(mouseUpAt: 100, panelVisible: false))
    }

    func testOpenCloseOpenSequence() {
        var tracker = StatusItemClickTracker()
        tracker.mouseDown(at: 10, panelVisible: false)
        XCTAssertFalse(tracker.clickClosesPanel(mouseUpAt: 10.1, panelVisible: false))   // opens
        tracker.mouseDown(at: 11, panelVisible: true)
        XCTAssertTrue(tracker.clickClosesPanel(mouseUpAt: 11.1, panelVisible: true))     // closes (toggle hide isn't "external")
        tracker.mouseDown(at: 11.5, panelVisible: false)
        XCTAssertFalse(tracker.clickClosesPanel(mouseUpAt: 11.6, panelVisible: false))   // opens again
    }
}
