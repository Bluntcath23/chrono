//
//  TimerPopoverView.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import SwiftUI
import CoreText

struct TimerPopoverView: View {
    @ObservedObject var viewModel: TimerViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Chrono")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white)
                .padding(.top, 20)
                .padding(.bottom, 24)
            
            // Large time display with tabular numbers to prevent shifting
            Text(viewModel.formattedTimeForPopover())
                .font(tabularNumberFont(size: 48))
                .foregroundColor(.white)
                .padding(.bottom, 32)
            
            // Buttons
            HStack(spacing: 12) {
                // Start/Stop button
                Button(action: {
                    if viewModel.isRunning {
                        viewModel.stop()
                    } else {
                        viewModel.start()
                    }
                }) {
                    Text(viewModel.isRunning ? "Stop" : "Start")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(white: 0.3))
                        )
                }
                .buttonStyle(.plain)
                
                // Reset button
                Button(action: {
                    viewModel.reset()
                }) {
                    Text("Reset")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(white: 0.3))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 220, height: 180)
        .background(Color.black)
    }
    
    // Helper function to create SF Pro font with tabular numbers
    private func tabularNumberFont(size: CGFloat) -> Font {
        let baseFont = NSFont.systemFont(ofSize: size, weight: .regular)
        
        // Get font descriptor with tabular numbers feature
        let fontDescriptor = baseFont.fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
                ]
            ]
        ])
        
        if let font = NSFont(descriptor: fontDescriptor, size: size) {
            return Font(font)
        }
        
        return Font.system(size: size, weight: .regular, design: .default)
    }
}

#Preview {
    TimerPopoverView(viewModel: TimerViewModel())
}

