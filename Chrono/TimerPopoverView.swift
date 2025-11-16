//
//  TimerPopoverView.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import SwiftUI
import CoreText
import AppKit

struct TimerPopoverView: View {
    @ObservedObject var viewModel: TimerViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            // Title
            Text("Chrono")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.top, 0)
            
            // Large time display with tabular numbers to prevent shifting
            Text(viewModel.formattedTimeForPopover())
                .font(tabularNumberFont(size: 32)) // revert to tabular number font
                .foregroundColor(.white)
                .padding(.bottom, 0)
            
            // Buttons
            HStack(spacing: 16) {
                // Start/Stop button
                Button(action: {
                    if viewModel.isRunning {
                        viewModel.stop()
                    } else {
                        viewModel.start()
                    }
                }) {
                    Text(viewModel.isRunning ? "Stop" : "Start")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: 70)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color(.sRGB, red: 0x5c/255.0, green: 0x5e/255.0, blue: 0x66/255.0, opacity: 1.0))
                        )
                }
                .buttonStyle(.plain)
                
                // Reset button
                Button(action: {
                    viewModel.reset()
                }) {
                    Text("Reset")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: 70)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color(.sRGB, red: 0x5c/255.0, green: 0x5e/255.0, blue: 0x66/255.0, opacity: 1.0))
                        )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity) // no fixed container width
        }
        .frame(width: 300) // height auto with spacings
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        // Use standard system popover chrome (no custom rounded background)
    }
}

// Glass/blur background using NSVisualEffectView for precise control on macOS.
private struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.blendingMode = .behindWindow
        if #available(macOS 15.0, *) {
            // More liquid glass-like material
            view.material = .hudWindow
        } else {
            // Older macOS: classic blurred material
            view.material = .menu
        }
        view.isEmphasized = true
        view.alphaValue = 0.85
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
        nsView.blendingMode = .behindWindow
        if #available(macOS 15.0, *) {
            nsView.material = .hudWindow
        } else {
            nsView.material = .menu
        }
        nsView.isEmphasized = true
        nsView.alphaValue = 0.85
    }
}

#if DEBUG
#Preview {
    TimerPopoverView(viewModel: TimerViewModel())
}
#endif

// Helper function to create SF Pro font with tabular numbers for stable digits
fileprivate func tabularNumberFont(size: CGFloat) -> Font {
    let baseFont = NSFont.systemFont(ofSize: size, weight: .regular)
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
    return Font.system(size: size, weight: .regular, design: .monospaced)
}

// Utility to allow percentage-based corner radius via GeometryReader
private struct GeometryReaderShape<S: Shape>: Shape {
    let builder: @Sendable (CGSize) -> S
    init(_ builder: @escaping @Sendable (CGSize) -> S) {
        self.builder = builder
    }
    func path(in rect: CGRect) -> Path {
        builder(rect.size).path(in: rect)
    }
}

