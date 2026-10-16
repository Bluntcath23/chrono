//
//  ChronoApp.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import SwiftUI
import AppKit
import UserNotifications

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
    private var store: ProjectStore?
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only (LSUIElement = YES also hides the Dock icon before this runs).
        NSApp.setActivationPolicy(.accessory)

        // Notification authorization is requested lazily (first timer start /
        // first auto-pause), not at launch.
        UNUserNotificationCenter.current().delegate = self

        let store = ProjectStore()
        let manager = MenuBarManager(store: store)
        self.store = store
        self.menuBarManager = manager
        manager.setup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarManager?.shutdown()
        store?.flush()
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
}
