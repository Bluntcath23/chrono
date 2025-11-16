//
//  ActivityMonitor.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import AppKit
import Combine
import IOKit
import IOKit.hid

class ActivityMonitor {
    private var lastActivityTime: Date = Date()
    private var monitorTimer: Timer?
    private var eventMonitor: Any?
    private let inactivityThreshold: TimeInterval = 300
    
    var onInactivityDetected: (() -> Void)?
    
    func startMonitoring() {
        lastActivityTime = Date()
        
        // Monitor mouse and keyboard events
        // Note: Requires accessibility permissions if app is sandboxed
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.lastActivityTime = Date()
        }
        
        if eventMonitor == nil {
            print("Warning: Could not set up global event monitoring. Activity detection may not work. Please grant accessibility permissions.")
        }
        
        // Check for inactivity every second on the main runloop (common modes)
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkInactivity()
        }
        monitorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    
    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
    
    func resetActivity() {
        lastActivityTime = Date()
    }
    
    private func checkInactivity() {
        let timeSinceLastActivity = Date().timeIntervalSince(lastActivityTime)
        let systemIdle = systemIdleTimeSeconds()
        let effectiveIdle = max(timeSinceLastActivity, systemIdle)
        
        if effectiveIdle >= inactivityThreshold {
            // Ensure handler runs on main (UI and MainActor-bound state)
            DispatchQueue.main.async { [weak self] in
                self?.onInactivityDetected?()
            }
            resetActivity() // Reset to avoid multiple notifications
        }
    }
    
    // Uses IOHIDSystem to get system-wide idle time (in seconds) without Accessibility permissions.
    private func systemIdleTimeSeconds() -> TimeInterval {
        let matching = IOServiceMatching("IOHIDSystem")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        
        var unmanaged: Unmanaged<CFTypeRef>?
        let key = "HIDIdleTime" as CFString
        let result = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)
        unmanaged = result
        guard let valueRef = unmanaged?.takeRetainedValue() else { return 0 }
        
        if let number = valueRef as? NSNumber {
            let nanoseconds = number.uint64Value
            return TimeInterval(Double(nanoseconds) / 1_000_000_000.0)
        }
        return 0
    }
    
    deinit {
        stopMonitoring()
    }
}

