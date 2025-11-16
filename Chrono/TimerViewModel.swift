//
//  TimerViewModel.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import Foundation
import Combine

@MainActor
class TimerViewModel: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    @Published var isRunning: Bool = false
    
    private var timer: Timer?
    private var startTime: Date?
    private var accumulatedTime: TimeInterval = 0
    
    func start() {
        guard !isRunning else { return }
        
        isRunning = true
        startTime = Date()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
    }
    
    func stop() {
        guard isRunning else { return }
        
        isRunning = false
        timer?.invalidate()
        timer = nil
        
        if let startTime = startTime {
            accumulatedTime += Date().timeIntervalSince(startTime)
            self.startTime = nil
        }
    }
    
    func reset() {
        stop()
        elapsed = 0
        accumulatedTime = 0
        startTime = nil
    }
    
    func formattedTime() -> String {
        let totalSeconds = Int(elapsed)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let tenths = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 10)
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, seconds, tenths)
        } else {
            return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
        }
    }
    
    func formattedTimeForPopover() -> String {
        // Format for popover: MM.SS.t (e.g., "01.15.7")
        let totalSeconds = Int(elapsed)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 10)
        
        return String(format: "%02d.%02d.%d", minutes, seconds, tenths)
    }
    
    private func updateElapsed() {
        if let startTime = startTime {
            elapsed = accumulatedTime + Date().timeIntervalSince(startTime)
        } else {
            elapsed = accumulatedTime
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

