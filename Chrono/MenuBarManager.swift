//
//  MenuBarManager.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import AppKit
import SwiftUI
import UserNotifications
import Combine

class MenuBarManager: NSObject, ObservableObject {
    private var statusBarItem: NSStatusItem?
    private var popover: NSPopover?
    private let viewModel: TimerViewModel
    private let activityMonitor: ActivityMonitor
    private let keyboardShortcutManager: KeyboardShortcutManager
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var timerView: TimerStatusBarView?
    
    init(viewModel: TimerViewModel) {
        self.viewModel = viewModel
        self.activityMonitor = ActivityMonitor()
        self.keyboardShortcutManager = KeyboardShortcutManager()
        
        super.init()
        
        setupActivityMonitor()
        setupKeyboardShortcuts()
        setupTimerObserver()
    }
    
    private func setupTimerObserver() {
        // Update menu bar text whenever elapsed time changes
        viewModel.$elapsed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarText()
            }
            .store(in: &cancellables)
    }
    
    private func updateMenuBarText() {
        guard let timerView = timerView else { return }
        
        let timeString = viewModel.formattedTime()
        timerView.updateTime(timeString)
    }
    
    func setup() {
        // Create status bar item on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Create status bar item with fixed width to prevent jittering
            self.statusBarItem = NSStatusBar.system.statusItem(withLength: 72)
            
            // Create custom view with rounded background
            let customView = TimerStatusBarView(frame: NSRect(x: 0, y: 0, width: 72, height: 20))
            customView.updateTime(self.viewModel.formattedTime())
            self.timerView = customView
            
            // Set up button with custom view
            if let button = self.statusBarItem?.button {
                // Make button transparent and add custom view
                button.title = ""
                button.image = nil
                button.imagePosition = .noImage
                
                // Add custom view as subview
                button.addSubview(customView)
                customView.frame = button.bounds
                customView.autoresizingMask = [.width, .height]
                
                // Set up click handler
                button.action = #selector(self.togglePopover)
                button.target = self
            }
            
            // Initial display
            self.updateMenuBarText()
            
            // Create popover
            self.popover = NSPopover()
            self.popover?.contentSize = NSSize(width: 220, height: 180)
            self.popover?.behavior = .transient
            self.popover?.delegate = self
            self.popover?.contentViewController = NSHostingController(rootView: TimerPopoverView(viewModel: self.viewModel))
            
            // Start monitoring - delay to ensure everything is set up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                self.activityMonitor.startMonitoring()
            }
            
            // Register keyboard shortcuts - delay to ensure app is fully initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                self.keyboardShortcutManager.registerShortcuts()
            }
        }
    }
    
    private func setupActivityMonitor() {
        activityMonitor.onInactivityDetected = { [weak self] in
            guard let self = self else { return }
            
            if self.viewModel.isRunning {
                self.viewModel.stop()
                self.sendNotification()
            }
        }
    }
    
    private func setupKeyboardShortcuts() {
        keyboardShortcutManager.onStartStop = { [weak self] in
            guard let self = self else { return }
            
            if self.viewModel.isRunning {
                self.viewModel.stop()
            } else {
                self.viewModel.start()
            }
            self.activityMonitor.resetActivity()
        }
        
        keyboardShortcutManager.onReset = { [weak self] in
            guard let self = self else { return }
            self.viewModel.reset()
            self.activityMonitor.resetActivity()
        }
    }
    
    @objc private func togglePopover() {
        guard let button = statusBarItem?.button else { return }
        
        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                // Show popover relative to the button
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
    
    private func sendNotification() {
        let notification = UNUserNotificationCenter.current()
        
        let content = UNMutableNotificationContent()
        content.title = "Chrono paused"
        content.body = "No activity detected for 5 minutes."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        notification.add(request)
    }
    
    deinit {
        updateTimer?.invalidate()
        cancellables.removeAll()
        activityMonitor.stopMonitoring()
        keyboardShortcutManager.unregisterShortcuts()
    }
}

extension MenuBarManager: NSPopoverDelegate {
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        return true
    }
}

