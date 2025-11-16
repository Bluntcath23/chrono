//
//  ChronoApp.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import SwiftUI
import AppKit
import UserNotifications
import Combine

@main
struct ChronoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	
	static let showOnboardingNotification = Notification.Name("Chrono.ShowOnboardingDebug")
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private var viewModel: TimerViewModel?
	private var onboardingWindow: NSWindow?
	private var cancellables: Set<AnyCancellable> = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
		// Hide dock icon while running (app will still appear in Launchpad if installed in /Applications)
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
		
		// Show onboarding on first launch
		showOnboardingIfNeeded()
		
		// Debug trigger to show onboarding from menu
		NotificationCenter.default.addObserver(
			forName: ChronoApp.showOnboardingNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.presentOnboarding(force: true)
		}
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        menuBarManager = nil
        viewModel = nil
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Prevent app from showing windows when clicking dock icon (shouldn't appear anyway)
        return false
    }
	
	private func showOnboardingIfNeeded() {
		let defaults = UserDefaults.standard
		let hasSeenOnboarding = defaults.bool(forKey: "hasSeenOnboarding")
		guard !hasSeenOnboarding else { return }
		
		let hosting = NSHostingController(rootView: OnboardingView(onFinish: { [weak self] in
			UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
			self?.onboardingWindow?.close()
			self?.onboardingWindow = nil
		}))
		
		let window = NSWindow(contentViewController: hosting)
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.styleMask = [.titled, .fullSizeContentView]
		window.standardWindowButton(.closeButton)?.isHidden = true
		window.standardWindowButton(.miniaturizeButton)?.isHidden = true
		window.standardWindowButton(.zoomButton)?.isHidden = true
		window.isOpaque = false
		window.backgroundColor = .clear
		window.setContentSize(NSSize(width: 720, height: 560))
		window.center()
		window.isReleasedWhenClosed = false
		window.level = .normal
		
		self.onboardingWindow = window
		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}
	
	// Present onboarding regardless of first-launch state (debug helper)
	private func presentOnboarding(force: Bool) {
		if onboardingWindow != nil {
			onboardingWindow?.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			return
		}
		
		let hosting = NSHostingController(rootView: OnboardingView(onFinish: { [weak self] in
			if !force {
				UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
			}
			self?.onboardingWindow?.close()
			self?.onboardingWindow = nil
		}))
		
		let window = NSWindow(contentViewController: hosting)
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.styleMask = [.titled, .fullSizeContentView]
		window.standardWindowButton(.closeButton)?.isHidden = true
		window.standardWindowButton(.miniaturizeButton)?.isHidden = true
		window.standardWindowButton(.zoomButton)?.isHidden = true
		window.isOpaque = false
		window.backgroundColor = .clear
		window.setContentSize(NSSize(width: 720, height: 560))
		window.center()
		window.isReleasedWhenClosed = false
		window.level = .normal
		
		self.onboardingWindow = window
		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}
}
