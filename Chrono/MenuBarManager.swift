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

@MainActor
class MenuBarManager: NSObject, ObservableObject {
    private var statusBarItem: NSStatusItem?
    private var popover: NSPopover?
    private let viewModel: TimerViewModel
    private let activityMonitor: ActivityMonitor
    private let keyboardShortcutManager: KeyboardShortcutManager
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var timerView: TimerStatusBarView?
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        let showWelcome = NSMenuItem(title: "Show Welcome", action: #selector(showWelcomePanel), keyEquivalent: "w")
        showWelcome.target = self
        menu.addItem(showWelcome)
        let quitItem = NSMenuItem(title: "Exit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }()
    
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
                self?.resizeStatusItemToFitText()
            }
            .store(in: &cancellables)
    }
    
    private func updateMenuBarText() {
        let timeString = viewModel.formattedTime()
        if let button = statusBarItem?.button {
            let image = renderStatusImage(for: timeString)
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else if let timerView = timerView {
            timerView.updateTime(timeString)
        }
    }
    
    private func resizeStatusItemToFitText() {
        guard let button = statusBarItem?.button else { return }
        let timeString = viewModel.formattedTime()
        
        // Measure text width roughly like the custom view does (13pt SF, tabular)
        let font = NSFont.systemFont(ofSize: 13, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let width = (timeString as NSString).size(withAttributes: attributes).width
        
        // Add horizontal padding and a little slack
        let targetWidth = max(72, ceil(width + 16))
        statusBarItem?.length = targetWidth
        button.setFrameSize(NSSize(width: targetWidth, height: button.frame.height))
    }
    
    func setup() {
        // Create status bar item on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Create status bar item using native button title (most reliable visibility)
            self.statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            
            // Set up button
            if let button = self.statusBarItem?.button {
                let timeString = self.viewModel.formattedTime()
                let image = self.renderStatusImage(for: timeString)
                button.image = image
                button.imagePosition = .imageOnly
                button.title = ""
                button.image = nil
                button.imagePosition = .noImage
                // Receive right-click actions as well
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                
                // Set up click handler
                button.action = #selector(self.togglePopover)
                button.target = self
            }
            
            // Initial display
            self.updateMenuBarText()
            
            // Create popover
            self.popover = NSPopover()
            self.popover?.contentSize = NSSize(width: 331, height: 129)
            self.popover?.behavior = .transient
            self.popover?.delegate = self
            // Hide the popover's arrow (anchor)
            self.popover?.setValue(true, forKey: "shouldHideAnchor")
            self.popover?.contentViewController = NSHostingController(rootView: TimerPopoverView(viewModel: self.viewModel))
            
            // Auto-open the popover once on first launch so the user sees the window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self,
                      let button = self.statusBarItem?.button,
                      let pop = self.popover else { return }
                if !pop.isShown {
                    pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                }
            }
            
            // If for any reason the status item didn't attach (very rare or menu bar hidden),
            // present a small floating window centered as a fallback so the user sees the app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self else { return }
                if self.statusBarItem?.button == nil {
                    self.presentCenteredFallbackWindow()
                }
            }
            
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
        
        keyboardShortcutManager.onQuit = { [weak self] in
            guard self != nil else { return }
            NSApp.terminate(nil)
        }
    }
    
    @objc private func togglePopover() {
        guard let button = statusBarItem?.button else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            // Show context menu on right-click
            NSMenu.popUpContextMenu(contextMenu, with: event, for: button)
            return
        }
        guard let pop = popover else { return }
        if pop.isShown {
            pop.performClose(nil)
        } else {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    @objc private func showWelcomePanel() {
        NotificationCenter.default.post(name: ChronoApp.showOnboardingNotification, object: nil)
    }
}

extension MenuBarManager: NSPopoverDelegate {
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        return true
    }
}

// MARK: - Fallback window
extension MenuBarManager {
    private func presentCenteredFallbackWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 160),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Use standard system titlebar/border
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.standardWindowButton(.zoomButton)?.isHidden = false
        panel.standardWindowButton(.closeButton)?.isHidden = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = false
        panel.level = .statusBar
        panel.isOpaque = true
        panel.backgroundColor = nil
        panel.contentView = NSHostingView(rootView: TimerPopoverView(viewModel: self.viewModel))
        
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
            panel.setFrameOrigin(origin)
        }
        
        panel.makeKeyAndOrderFront(nil)
        
        // Auto-close after a few seconds so it doesn't linger
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            panel.orderOut(nil)
        }
    }
}

// MARK: - Status item image rendering
extension MenuBarManager {
    private func renderStatusImage(for text: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 3
        let width = ceil(textSize.width + horizontalPadding * 2)
        let height = ceil(textSize.height + verticalPadding * 2)
        let size = NSSize(width: max(36, width), height: max(18, height))
        
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Gray pill background (#767680 @ 60%)
        let bgColor = NSColor(calibratedRed: 0x76/255.0, green: 0x76/255.0, blue: 0x80/255.0, alpha: 0.60)
        let rect = NSRect(origin: .zero, size: size)
        let radius = size.height / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        bgColor.setFill()
        path.fill()
        
        // Draw centered text in white
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2.0,
            y: (size.height - textSize.height) / 2.0 - 0.5,
            width: textSize.width,
            height: textSize.height
        )
        attributed.draw(in: textRect)
        
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
