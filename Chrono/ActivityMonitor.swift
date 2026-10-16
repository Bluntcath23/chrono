//
//  ActivityMonitor.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import Foundation
import CoreGraphics

/// Detects user inactivity by polling the system's "seconds since last input
/// event" counter. Needs no permissions (no event taps, no Input Monitoring),
/// so it works inside the App Sandbox.
///
/// Only polls while monitoring is on — `MenuBarManager` turns it on while the
/// timer runs and off when it stops, so an idle Chrono costs no wakeups.
@MainActor final class ActivityMonitor {
    /// Idle time after which a running timer is auto-paused.
    static let inactivityThreshold: TimeInterval = 300
    static let pollInterval: TimeInterval = 5

    /// Fired once per idle period with the date of the last user input.
    /// Re-arms once the user is active again.
    var onInactivityDetected: ((Date) -> Void)?

    private var timer: Timer?
    private var isArmed = true

    var isMonitoring: Bool { timer != nil }

    func startMonitoring() {
        guard timer == nil else { return }
        isArmed = true
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.poll()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let idle = Self.secondsSinceLastInput()
        guard idle >= Self.inactivityThreshold else {
            isArmed = true
            return
        }
        guard isArmed else { return }
        isArmed = false
        onInactivityDetected?(Date().addingTimeInterval(-idle))
    }

    /// Seconds since the last keyboard / mouse / trackpad event of any kind
    /// (`kCGAnyInputEventType`) in the current login session.
    nonisolated static func secondsSinceLastInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
