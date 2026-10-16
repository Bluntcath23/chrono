//
//  KeyboardShortcutManager.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import Foundation
import Carbon.HIToolbox
import os

/// Global hotkeys via Carbon `RegisterEventHotKey` — sandbox-safe and needs
/// no Accessibility / Input Monitoring permission.
///
/// Only two shortcuts are global: ⌘⇧S (start/stop) and ⌘⇧R (reset active).
/// Everything else (⌘N, ⌘Q, ⌘⇧1…9, …) is panel-local and handled by the UI.
///
/// Lifetime: owned by `MenuBarManager` for the whole app run. The Carbon
/// handler holds an unretained pointer to this object, so call
/// `unregisterShortcuts()` before releasing it (done in `MenuBarManager.shutdown()`).
@MainActor final class KeyboardShortcutManager {
    fileprivate nonisolated static let signature: OSType = 0x4348_524E // 'CHRN'
    static let log = Logger(subsystem: "com.inozemtsev.Chrono", category: "Hotkeys")

    fileprivate nonisolated enum HotKey: UInt32 {
        case startStop = 1
        case reset = 2
    }

    var onStartStop: (() -> Void)?
    var onReset: (() -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?

    func registerShortcuts() {
        unregisterShortcuts()
        guard installEventHandler() else { return }
        register(.startStop, keyCode: kVK_ANSI_S, description: "⌘⇧S")
        register(.reset, keyCode: kVK_ANSI_R, description: "⌘⇧R")
    }

    func unregisterShortcuts() {
        for ref in hotKeyRefs {
            let status = UnregisterEventHotKey(ref)
            if status != noErr {
                Self.log.error("UnregisterEventHotKey failed: \(status)")
            }
        }
        hotKeyRefs.removeAll()

        if let handler = eventHandlerRef {
            let status = RemoveEventHandler(handler)
            if status != noErr {
                Self.log.error("RemoveEventHandler failed: \(status)")
            }
            eventHandlerRef = nil
        }
    }

    fileprivate func handle(_ hotKey: HotKey) {
        switch hotKey {
        case .startStop: onStartStop?()
        case .reset: onReset?()
        }
    }

    // MARK: - Carbon

    private func installEventHandler() -> Bool {
        guard eventHandlerRef == nil else { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            chronoHotKeyHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        guard status == noErr else {
            Self.log.error("InstallEventHandler failed: \(status)")
            eventHandlerRef = nil
            return false
        }
        return true
    }

    private func register(_ hotKey: HotKey, keyCode: Int, description: String) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: hotKey.rawValue)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(cmdKey | shiftKey),
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
        } else if status == OSStatus(eventHotKeyExistsErr) {
            Self.log.error("Global shortcut \(description, privacy: .public) is already registered by another app")
        } else {
            Self.log.error("RegisterEventHotKey \(description, privacy: .public) failed: \(status)")
        }
    }
}

/// C callback for `kEventHotKeyPressed`. Carbon dispatches application-target
/// events on the main thread.
private nonisolated func chronoHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == KeyboardShortcutManager.signature,
          let hotKey = KeyboardShortcutManager.HotKey(rawValue: hotKeyID.id)
    else { return OSStatus(eventNotHandledErr) }

    let address = UInt(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<KeyboardShortcutManager>.fromOpaque(pointer).takeUnretainedValue().handle(hotKey)
    }
    return noErr
}
