//
//  ChronoApp.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import SwiftUI
import AppKit
import UserNotifications
import os

@main
struct ChronoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let log = Logger(subsystem: "com.inozemtsev.Chrono", category: "App")
    /// How long to wait for a previous instance that is still quitting (a quick
    /// quit → relaunch) before treating it as a second running copy.
    private static let otherInstanceGracePeriod: Duration = .seconds(3)

    private var store: ProjectStore?
    private var menuBarManager: MenuBarManager?
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only (LSUIElement = YES also hides the Dock icon before this runs).
        NSApp.setActivationPolicy(.accessory)

        // Notification authorization is requested lazily (first timer start /
        // first auto-pause), not at launch.
        UNUserNotificationCenter.current().delegate = self

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        Self.log.notice("launch \(version, privacy: .public) (\(build, privacy: .public)) pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) sandboxed=\(sandboxed, privacy: .public) bundle=\(Bundle.main.bundlePath, privacy: .public)")

        Task { @MainActor in
            // Two copies at once (e.g. an installed build and an Xcode run) both
            // rewrite projects.json from their own in-memory state, so the last
            // writer silently wins. Copies with different storage (sandboxed vs
            // not) show different project lists. Only ever run one.
            if let other = await Self.otherRunningInstance() {
                Self.log.fault("another Chrono instance is running (pid \(other.processIdentifier, privacy: .public), \(other.bundleURL?.path ?? "?", privacy: .public)); quitting this one")
                Self.showAlreadyRunningAlert(other)
                NSApp.terminate(nil)
                return
            }
            self.start()
        }
    }

    @MainActor private func start() {
        let store = ProjectStore()
        let manager = MenuBarManager(store: store)
        self.store = store
        self.menuBarManager = manager
        manager.setup()
        installTerminationSignalHandler()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarManager?.shutdown()
        store?.flush(source: "applicationWillTerminate")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    // Show auto-pause notifications even while Chrono is the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    // MARK: - Single instance

    /// Another live process with our bundle identifier, after giving one that
    /// is already quitting a moment to finish.
    @MainActor private static func otherRunningInstance() async -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        func find() -> NSRunningApplication? {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first { $0.processIdentifier != ownPID && !$0.isTerminated }
        }
        let deadline = ContinuousClock.now + otherInstanceGracePeriod
        while let other = find() {
            guard ContinuousClock.now < deadline else { return other }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    @MainActor private static func showAlreadyRunningAlert(_ other: NSRunningApplication) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Chrono is already running"
        let location = other.bundleURL?.path ?? "another location"
        alert.informativeText = "Another copy of Chrono is open (\(location)). Running two copies at once can overwrite your tracked time, so this one will quit. Use the timer in the menu bar, or quit it first."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - SIGTERM

    /// `kill <pid>`, `pkill Chrono` and some updaters send SIGTERM, which by
    /// default ends the process without `applicationWillTerminate`, so a
    /// running timer lost everything since its last checkpoint. Route it
    /// through the normal quit path so the store is flushed.
    @MainActor private func installTerminationSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            Self.log.notice("SIGTERM received; quitting cleanly")
            NSApp.terminate(nil)
        }
        source.resume()
        terminationSignal = source
    }
}
