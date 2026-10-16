//
//  TimeFormat.swift
//  Chrono
//
//  Created by Ivan Inozemtsev on 16.10.26.
//

import Foundation

/// Shared time formatting. All values are truncated, never rounded up.
nonisolated enum TimeFormat {
    /// Guards against binary floating-point error (e.g. x.3 * 10 = 2.9999…).
    private static let epsilon: Double = 1e-9

    /// < 1 h: `MM:SS.t` (e.g. "04:12.6"). ≥ 1 h: `H:MM:SS` (e.g. "1:25:06").
    static func clock(_ t: TimeInterval) -> String {
        let value = sanitized(t)
        if value < 3600 {
            let totalTenths = Int((value * 10 + epsilon).rounded(.down))
            let tenths = totalTenths % 10
            let totalSeconds = totalTenths / 10
            return String(format: "%02d:%02d.%d", totalSeconds / 60, totalSeconds % 60, tenths)
        }
        let totalSeconds = Int(value)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    /// `Hh MMm` with truncated minutes (e.g. "0h 40m", "10h 21m").
    static func duration(_ t: TimeInterval) -> String {
        let totalMinutes = Int(sanitized(t)) / 60
        return String(format: "%dh %02dm", totalMinutes / 60, totalMinutes % 60)
    }

    private static func sanitized(_ t: TimeInterval) -> TimeInterval {
        guard t.isFinite, t > 0 else { return 0 }
        // Cap absurd values so Int conversion can never trap (~11 400 years).
        return min(t, 3.6e11)
    }
}
