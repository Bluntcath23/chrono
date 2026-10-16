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
