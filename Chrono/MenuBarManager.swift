//
//  MenuBarManager.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import AppKit
import SwiftUI
import Combine
import UserNotifications
import os

/// Borderless floating panel. Must be able to become key so SwiftUI focus,
/// text fields, `.onKeyPress` and `.keyboardShortcut` work inside it.
///
/// While open, the window is a fixed, tall, mostly transparent canvas; the
/// visible panel occupies its top `visibleHeight` points (see `MenuBarManager`).
final class ChronoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Height of the visible panel at the top of the window.
    var visibleHeight: CGFloat = .greatestFiniteMagnitude
    /// Called for a mouse-down that reaches the window below the visible panel.
    var onMouseDownOutsideChrome: (() -> Void)?

    /// Fallback for click-through: normally the window server sends clicks on
    /// the transparent canvas to the app behind (per-pixel alpha hit testing,
    /// which only applies while `ignoresMouseEvents` is never assigned). If a
    /// click lands there anyway, treat it as an outside click.
    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
           event.locationInWindow.y < frame.height - visibleHeight {
            onMouseDownOutsideChrome?()
            return
        }
        super.sendEvent(event)
    }

    /// VoiceOver and window screenshots should see the visible panel, not the canvas.
    override func accessibilityFrame() -> NSRect {
        var visible = frame
        visible.size.height = min(visibleHeight, frame.height)
        visible.origin.y = frame.maxY - visible.size.height
        return visible
    }
}

/// Owns the status item, the floating panel, global hotkeys and auto-pause.
///
/// Windowing rules (see AGENTS.md): no `NSPopover`; the panel's TOP edge is
/// pinned on every resize and frames are applied instantly (`animate: false`)
/// once per reported size, so AppKit never competes with SwiftUI animations.
@MainActor final class MenuBarManager: NSObject, NSMenuDelegate {
    private enum Layout {
        /// Gap between the menu bar and the top of the panel.
        static let menuBarGap: CGFloat = 8
        /// Minimum distance from the screen's visible frame edges.
        static let screenMargin: CGFloat = 8
        static let fallbackHeight: CGFloat = 200
        /// Fixed height of the (mostly transparent) panel window while it is open.
        /// Taller than any panel state (main ≤ ~600 pt incl. a confirmation card,
        /// Info ≈ 416 pt), so transitions never resize the window — see `showPanel`.
        static let windowHeight: CGFloat = 720
    }

    private static let log = Logger(subsystem: "com.inozemtsev.Chrono", category: "Panel")
    private static let firstLaunchDefaultsKey = "didShowFirstLaunchPanel"
    private static let statusFont = NSFont.monospacedDigitSystemFont(
        ofSize: TimerStatusBarView.Metrics.fontSize, weight: .medium
    )

    private let store: ProjectStore
    private let launchAtLogin = LaunchAtLogin()
    private let activityMonitor = ActivityMonitor()
    private let shortcuts = KeyboardShortcutManager()
    private let notifier = AutoPauseNotifier()
    private let pillState = StatusPillState()

    private var statusItem: NSStatusItem?
    private var panel: ChronoPanel?
    private var reportedContentHeight: CGFloat?
    private var globalMouseMonitor: Any?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var cancellables = Set<AnyCancellable>()
    private var lastAccessibilityLabel = ""
    private var shadowTimer: Timer?

    private lazy var statusMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        let open = NSMenuItem(title: "Open Chrono", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Chrono", action: #selector(quit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        quit.target = self
        menu.addItem(quit)
        return menu
    }()

    init(store: ProjectStore) {
        self.store = store
        super.init()
    }

    // MARK: - Lifecycle

    func setup() {
        setupStatusItem()
        setupPanel()
        setupStoreObservers()
        setupSystemObservers()
        setupShortcuts()
        setupAutoPause()
        refreshStatusItem()
        showOnFirstLaunchIfNeeded()
    }

    /// Explicit teardown (called from `applicationWillTerminate`) instead of a
    /// nonisolated `deinit` touching main-actor state.
    func shutdown() {
        removeGlobalMouseMonitor()
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
        cancellables.removeAll()
        activityMonitor.stopMonitoring()
        shortcuts.unregisterShortcuts()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }

        button.title = ""
        button.image = nil
        button.imagePosition = .noImage
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let pill = TimerStatusBarView(store: store, pill: pillState).allowsHitTesting(false)
        let host = NSHostingView(rootView: pill)
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            host.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isSecondaryClick {
            hidePanel(reason: "status item right-click")
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func showStatusMenu() {
        guard let statusItem, let button = statusItem.button else { return }
        // Standard trick: attach the menu just for this click so AppKit
        // positions and highlights it like a native status menu.
        statusItem.menu = statusMenu
        button.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === statusMenu {
            statusItem?.menu = nil
        }
    }

    @objc private func openFromMenu() {
        // Let the menu finish closing before the panel takes key.
        Task { @MainActor [weak self] in self?.showPanel() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Sets the status item width from the monospaced-digit text width, so it
    /// only changes when the format changes length (59:59.9 → 1:00:00).
    private func resizeStatusItemToFitText() {
        guard let statusItem else { return }
        let text = TimeFormat.clock(store.activeElapsed) as NSString
        let textWidth = text.size(withAttributes: [.font: Self.statusFont]).width
        let width = ceil(textWidth + 2 * TimerStatusBarView.Metrics.horizontalPadding)
        if abs(statusItem.length - width) > 0.5 {
            statusItem.length = width
        }
    }

    private func refreshStatusItem() {
        resizeStatusItemToFitText()
        guard let button = statusItem?.button else { return }
        let state = store.isRunning ? "running" : "paused"
        let label = "Chrono, \(store.activeProject.name), \(TimeFormat.clock(store.activeElapsed)), \(state)"
        if label != lastAccessibilityLabel {
            lastAccessibilityLabel = label
            button.setAccessibilityLabel(label)
        }
    }

    // MARK: - Panel

    private func setupPanel() {
        let panel = ChronoPanel(
            contentRect: NSRect(x: 0, y: 0, width: Theme.Panel.width, height: Layout.fallbackHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        // `ignoresMouseEvents` stays at its default ("auto"): fully transparent
        // pixels below the visible panel pass clicks through to the app behind
        // (the outside-click monitor then closes the panel), while the panel
        // itself has a faint hit fill (see `TimerPopoverView.panelBackground`).
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let root = TimerPopoverView(
            store: store,
            launchAtLogin: launchAtLogin,
            onSizeChange: { [weak self] size in self?.handleSizeChange(size) },
            onClose: { [weak self] in self?.hidePanel(reason: "onClose (Esc / UI)", restoreFocus: true) },
            onResizeAnimation: { [weak self] duration in self?.trackShadow(for: duration) }
        )
        // Never assign `panel.ignoresMouseEvents`: even `false` switches off the
        // per-pixel click-through of the transparent canvas below the panel.
        panel.onMouseDownOutsideChrome = { [weak self] in
            self?.hidePanel(reason: "click on transparent canvas")
        }
        let host = NSHostingView(rootView: root)
        // We own the window frame; don't let the hosting view resize the window.
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
    }

    private var isPanelVisible: Bool { panel?.isVisible == true }

    private func togglePanel() {
        if isPanelVisible {
            hidePanel(reason: "status item click", restoreFocus: true)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel, !panel.isVisible,
              let button = statusItem?.button,
              let buttonWindow = button.window
        else { return }

        launchAtLogin.refresh()

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen
            ?? NSScreen.screens.first(where: { $0.frame.intersects(buttonRect) })
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? buttonRect

        let width = Theme.Panel.width
        let centeredX = buttonRect.midX - width / 2
        let x = max(visible.minX + Layout.screenMargin,
                    min(centeredX, visible.maxX - Layout.screenMargin - width))
        let top = min(buttonRect.minY, visible.maxY) - Layout.menuBarGap

        // The window is a fixed, tall, transparent canvas; the visible glass panel
        // is drawn at its top and animates its own bottom edge in SwiftUI. Resizing
        // the window during a transition made the window server present the new
        // content and the new frame in different frames, so the whole panel
        // visibly jumped up and back (e.g. when the delete confirmation opened).
        let contentHeight = max(Layout.windowHeight, reportedContentHeight ?? Layout.fallbackHeight)
        let height = clampedHeight(contentHeight, top: top, visibleFrame: visible)

        panel.setFrame(NSRect(x: x, y: top - height, width: width, height: height),
                       display: false, animate: false)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        panel.invalidateShadow()

        pillState.isPanelOpen = true
        installGlobalMouseMonitor()
    }

    /// The single hide path. Idempotent, so overlapping triggers (outside
    /// click + app resign) post `.chronoPanelDidClose` exactly once.
    /// - Parameter restoreFocus: give focus back to the previously active app
    ///   (status item click / Esc). Not needed when another app is already
    ///   taking focus (outside click, resign active).
    private func hidePanel(reason: String, restoreFocus: Bool = false) {
        guard let panel, panel.isVisible else { return }
        Self.log.info("hide panel: \(reason, privacy: .public)")
        panel.orderOut(nil)
        removeGlobalMouseMonitor()
        pillState.isPanelOpen = false
        NotificationCenter.default.post(name: .chronoPanelDidClose, object: nil)
        if restoreFocus, NSApp.isActive {
            NSApp.deactivate()
        }
    }

    /// Records the size reported by SwiftUI. The open window normally already has
    /// room (fixed `Layout.windowHeight`), so nothing changes; it only grows —
    /// top edge pinned, instant — in the unexpected case that content is taller.
    private func handleSizeChange(_ size: CGSize) {
        guard size.height > 0, size.height.isFinite else { return }
        Self.log.debug("size change: \(size.height, privacy: .public)")
        reportedContentHeight = size.height
        panel?.visibleHeight = size.height
        guard let panel, panel.isVisible else { return }   // positioned on show

        let top = panel.frame.maxY
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        let height = clampedHeight(size.height, top: top, visibleFrame: visible)
        guard height > panel.frame.height + 0.5 else { return }
        // Unexpected with the fixed canvas; a resize here could bring back the jump.
        Self.log.error("panel content (\(size.height, privacy: .public)) outgrew the canvas; growing window")

        var frame = panel.frame
        frame.origin.y = top - height
        frame.size.height = height
        frame.size.width = Theme.Panel.width
        panel.setFrame(frame, display: true, animate: false)
        panel.invalidateShadow()
    }

    /// The panel shadow is derived from the window's contents and doesn't follow
    /// SwiftUI animations on its own, so refresh it every frame while the chrome
    /// height animates.
    private func trackShadow(for duration: TimeInterval) {
        shadowTimer?.invalidate()
        let deadline = Date().addingTimeInterval(duration + 0.05)
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible, Date() < deadline else {
                    timer.invalidate()
                    self?.panel?.invalidateShadow()
                    return
                }
                panel.invalidateShadow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        shadowTimer = timer
    }

    /// Never extend below the visible frame. Known limitation: the list only
    /// scrolls past 8 rows, so on a very short screen the bottom of a tall panel
    /// (e.g. 8 rows + a confirmation card) is clipped at the window edge.
    private func clampedHeight(_ height: CGFloat, top: CGFloat, visibleFrame: NSRect) -> CGFloat {
        let available = top - (visibleFrame.minY + Layout.screenMargin)
        return max(1, min(height, available))
    }

    private func installGlobalMouseMonitor() {
        guard globalMouseMonitor == nil else { return }
        // Global monitors only see events delivered to OTHER apps, so clicks
        // inside the panel, its context menus and our status item never land here.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel(reason: "click outside (global monitor)") }
        }
    }

    private func removeGlobalMouseMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }

    private func showOnFirstLaunchIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.firstLaunchDefaultsKey) else { return }
        defaults.set(true, forKey: Self.firstLaunchDefaultsKey)
        // Give the status item a moment to get its on-screen position.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.showPanel()
        }
    }

    // MARK: - Observers

    private func setupStoreObservers() {
        // objectWillChange fires before the mutation; hop to the next main
        // run-loop turn so we read the new values. Covers tick, running state,
        // active project and renames.
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &cancellables)

        store.$isRunning
            .removeDuplicates()
            .sink { [weak self] isRunning in
                guard let self else { return }
                if isRunning {
                    self.activityMonitor.startMonitoring()
                    self.notifier.requestAuthorizationIfNeeded()
                } else {
                    self.activityMonitor.stopMonitoring()
                }
            }
            .store(in: &cancellables)
    }

    private func setupSystemObservers() {
        let local = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observe(local, NSApplication.didResignActiveNotification) { manager in
            manager.hidePanel(reason: "app resigned active")
        }
        observe(workspace, NSWorkspace.willSleepNotification) { manager in
            manager.autoPause(reason: "Mac went to sleep")
        }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { manager in
            manager.autoPause(reason: "screen locked")
        }
        observe(workspace, NSWorkspace.willPowerOffNotification) { manager in
            manager.store.flush()
        }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        handler: @escaping @MainActor (MenuBarManager) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    // MARK: - Shortcuts & auto-pause

    private func setupShortcuts() {
        shortcuts.onStartStop = { [weak self] in self?.store.toggle() }
        shortcuts.onReset = { [weak self] in self?.store.resetActive() }
        shortcuts.registerShortcuts()
    }

    private func setupAutoPause() {
        activityMonitor.onInactivityDetected = { [weak self] lastActivity in
            guard let self, self.store.isRunning else { return }
            let name = self.store.activeProject.name
            self.store.stop(creditingUntil: lastActivity)
            let minutes = max(1, Int(Date().timeIntervalSince(lastActivity) / 60))
            self.notifier.post("\(name) paused — away for \(minutes) min")
        }
    }

    private func autoPause(reason: String) {
        guard store.isRunning else { return }
        let name = store.activeProject.name
        store.stop()
        notifier.post("\(name) paused — \(reason)")
    }
}

// MARK: - Notifications

/// Posts auto-pause notifications. Authorization is requested lazily — on the
/// first timer start or the first notification — never at launch.
@MainActor final class AutoPauseNotifier {
    private var hasRequested = false

    func requestAuthorizationIfNeeded() {
        guard !hasRequested else { return }
        hasRequested = true
        Task { _ = await Self.authorize() }
    }

    func post(_ body: String) {
        hasRequested = true
        Task {
            guard await Self.authorize() else { return }
            let content = UNMutableNotificationContent()
            content.title = "Chrono"
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("AutoPauseNotifier: could not deliver notification: \(error)")
            }
        }
    }

    private static func authorize() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                print("AutoPauseNotifier: authorization failed: \(error)")
                return false
            }
        default:
            return false
        }
    }
}
