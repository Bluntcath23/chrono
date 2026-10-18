//
//  ActivityMonitor.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import Foundation
import CoreGraphics
import os

/// Detects user inactivity from the system's "seconds since last input event"
/// counter. Needs no permissions (no event taps, no Input Monitoring), so it
/// works inside the App Sandbox.
///
/// Only runs while monitoring is on — `MenuBarManager` turns it on while the
/// timer runs and off when it stops.
///
/// Timing: instead of polling blindly, each check schedules the next one for
/// the moment the idle time would reach the threshold (capped at
/// `maxCheckInterval`, so a sleep/wake or a missed reading self-corrects).
/// While monitoring, an App Nap–preventing activity is held: with the panel
/// closed Chrono has no visible window, and App Nap would otherwise defer its
/// timers by minutes (the auto-pause used to fire ~10 min late).
@MainActor final class ActivityMonitor {
    nonisolated static let defaultThreshold: TimeInterval = 300
    nonisolated static let minimumThreshold: TimeInterval = 5
    /// Testing override, in seconds: `defaults write com.inozemtsev.Chrono
    /// ChronoIdleThresholdSeconds 20`, or launch with `-ChronoIdleThresholdSeconds 20`.
    nonisolated static let thresholdDefaultsKey = "ChronoIdleThresholdSeconds"
    /// Longest gap between two checks.
    static let maxCheckInterval: TimeInterval = 30

    /// The idle threshold from `UserDefaults` (launch arguments included),
    /// clamped to ≥ `minimumThreshold`; `defaultThreshold` when unset.
    nonisolated static var configuredThreshold: TimeInterval {
        let value = UserDefaults.standard.double(forKey: thresholdDefaultsKey)
        guard value.isFinite, value > 0 else { return defaultThreshold }
        return max(minimumThreshold, value)
    }

    private static let log = Logger(subsystem: "com.inozemtsev.Chrono", category: "Idle")

    /// Idle time after which a running timer is auto-paused.
    let threshold: TimeInterval

    /// Fired once per idle period with the date of the last user input.
    /// Re-arms once the user is active again.
    var onInactivityDetected: ((Date) -> Void)?

    private(set) var isMonitoring = false
    private let idleSeconds: () -> TimeInterval
    private let now: () -> Date
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var isArmed = true

    init(
        threshold: TimeInterval = ActivityMonitor.configuredThreshold,
        idleSeconds: @escaping () -> TimeInterval = ActivityMonitor.secondsSinceLastInput,
        now: @escaping () -> Date = Date.init
    ) {
        self.threshold = threshold
        self.idleSeconds = idleSeconds
        self.now = now
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        isArmed = true
        // Public, App Store–safe; still allows the Mac to idle-sleep (sleep is
        // handled separately as an immediate pause).
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Timing a project"
        )
        Self.log.notice("monitoring started, threshold=\(self.threshold, privacy: .public)s")
        check()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        Self.log.notice("monitoring stopped")
    }

    /// Reads the idle time, fires if the threshold is reached, and schedules
    /// the next check. Internal so tests can drive it.
    func check() {
        guard isMonitoring else { return }
        let idle = max(0, idleSeconds())
        let next: TimeInterval
        if idle >= threshold {
            next = Self.maxCheckInterval
            if isArmed {
                isArmed = false
                let lastInput = now().addingTimeInterval(-idle)
                Self.log.notice("idle threshold reached: idle=\(idle, privacy: .public)s lastInput=\(lastInput.timeIntervalSince1970, privacy: .public)")
                onInactivityDetected?(lastInput)
            }
        } else {
            isArmed = true
            // Land just past the threshold so the next reading is ≥ it.
            next = min(threshold - idle + 0.05, Self.maxCheckInterval)
        }
        Self.log.debug("idle check: idle=\(idle, privacy: .public)s next=\(next, privacy: .public)s")
        schedule(after: next)
    }

    private func schedule(after interval: TimeInterval) {
        timer?.invalidate()
        guard isMonitoring else { return }
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = min(0.5, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Seconds since the last keyboard / mouse / trackpad event of any kind
    /// (`kCGAnyInputEventType`) in the current login session.
    nonisolated static func secondsSinceLastInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
