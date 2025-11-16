//
//  KeyboardShortcutManager.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import AppKit
import CoreGraphics

class KeyboardShortcutManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private static var activeManagers: [UnsafeMutableRawPointer: KeyboardShortcutManager] = [:]
    private var managerKey: UnsafeMutableRawPointer?
    
    var onStartStop: (() -> Void)?
    var onReset: (() -> Void)?
    
    func registerShortcuts() {
        // Create manager key now that self is fully initialized
        let key = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        managerKey = key
        
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        
        // Retain self for the callback
        KeyboardShortcutManager.activeManagers[key] = self
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                
                guard let manager = KeyboardShortcutManager.activeManagers[refcon] else {
                    return Unmanaged.passUnretained(event)
                }
                
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags
                    
                    // Check for ⌘⇧S (Start/Stop)
                    // S key code: 1 (US keyboard layout)
                    if keyCode == 1 &&
                       flags.contains(.maskCommand) &&
                       flags.contains(.maskShift) {
                        DispatchQueue.main.async {
                            manager.onStartStop?()
                        }
                        return nil // Consume the event
                    }
                    
                    // Check for ⌘⇧R (Reset)
                    // R key code: 15 (US keyboard layout)
                    if keyCode == 15 &&
                       flags.contains(.maskCommand) &&
                       flags.contains(.maskShift) {
                        DispatchQueue.main.async {
                            manager.onReset?()
                        }
                        return nil // Consume the event
                    }
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: key
        )
        
        guard let eventTap = eventTap else {
            KeyboardShortcutManager.activeManagers.removeValue(forKey: key)
            managerKey = nil
            print("Failed to create event tap. Please grant accessibility permissions in System Settings.")
            return
        }
        
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }
    
    func unregisterShortcuts() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        
        // Remove from active managers
        if let key = managerKey {
            KeyboardShortcutManager.activeManagers.removeValue(forKey: key)
            managerKey = nil
        }
    }
    
    deinit {
        unregisterShortcuts()
    }
}

