//
//  LaunchAtLogin.swift
//  Chrono
//
//  Created by Ivan Inozemtsev on 16.10.26.
//

import Foundation
import Combine
import ServiceManagement

/// Opt-in "Launch at login" via `SMAppService` (sandbox / App Store safe).
/// Off by default — the system only registers the app when the user turns it on.
@MainActor final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled: Bool = false

    init() {
        refresh()
    }

    /// Re-reads the system state (the user can also change it in System Settings → Login Items).
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("LaunchAtLogin: \(enabled ? "register" : "unregister") failed: \(error)")
        }
        refresh()
    }
}
