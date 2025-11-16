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

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private var viewModel: TimerViewModel?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
        
        // Create and setup menu bar
        let vm = TimerViewModel()
        let mbm = MenuBarManager(viewModel: vm)
        
        // Store references first to prevent deallocation
        self.viewModel = vm
        self.menuBarManager = mbm
        
        // Then setup (which is now async)
        mbm.setup()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        menuBarManager = nil
        viewModel = nil
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Prevent app from showing windows when clicking dock icon (shouldn't appear anyway)
        return false
    }
}
