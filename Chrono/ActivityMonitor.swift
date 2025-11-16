//
//  ActivityMonitor.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import AppKit
import Combine

class ActivityMonitor {
    private var lastActivityTime: Date = Date()
    private var monitorTimer: Timer?
    private var eventMonitor: Any?
    private let inactivityThreshold: TimeInterval = 300 // 5 minutes
    
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
        
        // Check for inactivity every 10 seconds
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkInactivity()
        }
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
        
        if timeSinceLastActivity >= inactivityThreshold {
            onInactivityDetected?()
            resetActivity() // Reset to avoid multiple notifications
        }
    }
    
    deinit {
        stopMonitoring()
    }
}

