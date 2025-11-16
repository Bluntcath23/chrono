//
//  KeyboardShortcutManager.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import AppKit
import CoreGraphics
import Carbon.HIToolbox

class KeyboardShortcutManager {
    // Carbon hotkey references
    private var startStopHotKeyRef: EventHotKeyRef?
    private var resetHotKeyRef: EventHotKeyRef?
    private var quitHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    var onStartStop: (() -> Void)?
    var onReset: (() -> Void)?
    var onQuit: (() -> Void)?
    
    func registerShortcuts() {
        unregisterShortcuts()
        
        // Install a Carbon event handler once to receive hotkey events
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            
            var hotKeyID = EventHotKeyID()
            GetEventParameter(theEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            switch hotKeyID.id {
            case 1:
                DispatchQueue.main.async { manager.onStartStop?() }
            case 2:
                DispatchQueue.main.async { manager.onReset?() }
            case 3:
                DispatchQueue.main.async { manager.onQuit?() }
            default:
                break
            }
            return noErr
        }, 1, &eventType, selfPointer, &eventHandlerRef)
        
        // Register ⌘⇧S
        let startID = EventHotKeyID(signature: OSType(0x4348524E), id: 1) // 'CHRN'
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(cmdKey | shiftKey), startID, GetApplicationEventTarget(), 0, &startStopHotKeyRef)
        
        // Register ⌘⇧R
        let resetID = EventHotKeyID(signature: OSType(0x4348524E), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(cmdKey | shiftKey), resetID, GetApplicationEventTarget(), 0, &resetHotKeyRef)
        
        // Register ⌘Q
        let quitID = EventHotKeyID(signature: OSType(0x4348524E), id: 3)
        RegisterEventHotKey(UInt32(kVK_ANSI_Q), UInt32(cmdKey), quitID, GetApplicationEventTarget(), 0, &quitHotKeyRef)
    }
    
    func unregisterShortcuts() {
        if let ref = startStopHotKeyRef {
            UnregisterEventHotKey(ref)
            startStopHotKeyRef = nil
        }
        if let ref = resetHotKeyRef {
            UnregisterEventHotKey(ref)
            resetHotKeyRef = nil
        }
        if let ref = quitHotKeyRef {
            UnregisterEventHotKey(ref)
            quitHotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
    
    deinit {
        unregisterShortcuts()
    }
}

