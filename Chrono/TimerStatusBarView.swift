//
//  TimerStatusBarView.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import SwiftUI
import Combine

/// Panel visibility, mirrored into the menu bar pill (brighter fill while open).
@MainActor final class StatusPillState: ObservableObject {
    @Published var isPanelOpen = false
}

/// Decides whether a left click on the status item should close the panel or
/// open it, so the status item is a clean toggle.
///
/// The panel can be hidden by something else in the middle of that very click
/// (the outside-click monitor, the app resigning active, …) before the button
/// sends its action on mouse-up. The action then saw a hidden panel and
/// reopened it: close-then-reopen, so clicking the pill never closed the
/// panel. This remembers whether the panel was open when the click began.
///
/// Times are `systemUptime` seconds (the clock of `NSEvent.timestamp`).
nonisolated struct StatusItemClickTracker {
    /// A recorded mouse-down older than this is stale (its mouse-up never arrived).
    static let maxClickDuration: TimeInterval = 10
    /// Slack for a hide whose timestamp is a hair earlier than the mouse-down event.
    static let hideTolerance: TimeInterval = 0.05
    /// With no mouse-down seen, a hide this recent counts as part of the click.
    static let fallbackWindow: TimeInterval = 0.5

    private var mouseDownUptime: TimeInterval?
    private var panelOpenAtMouseDown = false
    /// Last time the panel was hidden by anything other than a status item click.
    private var lastExternalHideUptime: TimeInterval?

    init() {}

    mutating func mouseDown(at uptime: TimeInterval, panelVisible: Bool) {
        mouseDownUptime = uptime
        panelOpenAtMouseDown = panelVisible
    }

    mutating func panelHiddenExternally(at uptime: TimeInterval) {
        lastExternalHideUptime = uptime
    }

    /// Called from the button's mouse-up action. True: the panel was open when
    /// this click began, so the click closes it (and must not reopen it).
    mutating func clickClosesPanel(mouseUpAt uptime: TimeInterval, panelVisible: Bool) -> Bool {
        defer {
            mouseDownUptime = nil
            panelOpenAtMouseDown = false
        }
        if panelVisible { return true }
        if let down = mouseDownUptime, down <= uptime + Self.hideTolerance, uptime - down < Self.maxClickDuration {
            if panelOpenAtMouseDown { return true }
            if let hide = lastExternalHideUptime, hide >= down - Self.hideTolerance { return true }
            return false
        }
        if let hide = lastExternalHideUptime, hide >= uptime - Self.fallbackWindow { return true }
        return false
    }
}

/// Menu bar pill. `MenuBarManager.resizeStatusItemToFitText()` sizes the
/// status item from the same font + padding, so keep `Metrics` in sync.
struct TimerStatusBarView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var pill: StatusPillState

    nonisolated enum Metrics {
        static let fontSize: CGFloat = 13
        static let height: CGFloat = 22
        static let horizontalPadding: CGFloat = 8
    }

    var body: some View {
        Text(TimeFormat.clock(store.activeElapsed))
            .font(.system(size: Metrics.fontSize, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.primary.opacity(store.isRunning ? 1.0 : 0.75))
            .padding(.horizontal, Metrics.horizontalPadding)
            .frame(height: Metrics.height)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(pill.isPanelOpen ? 0.24 : 0.15))
            )
            .fixedSize(horizontal: true, vertical: false)
            // The status button carries the accessibility label.
            .accessibilityHidden(true)
    }
}
