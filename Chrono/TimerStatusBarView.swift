//
//  TimerStatusBarView.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import AppKit
import CoreText

class TimerStatusBarView: NSView {
    private var timeString: String = "00:00.0" {
        didSet {
            needsDisplay = true
        }
    }
    
    private let fixedWidth: CGFloat = 72 // Fixed width to prevent jittering (minimal padding for "2:01:25.6")
    private let padding: CGFloat = 8
    private let visualEffectView = NSVisualEffectView(frame: .zero)
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = true
        
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        if #available(macOS 15.0, *) {
            // Newer macOS: more liquid glass-like material
            visualEffectView.material = .hudWindow
        } else {
            // Older macOS: standard blurred menu material
            visualEffectView.material = .menu
        }
        addSubview(visualEffectView, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        layer?.cornerRadius = bounds.height / 2
        // Make view non-interactive so clicks pass through to button
        isHidden = false
    }
    
    override var isOpaque: Bool { false }
    
    func updateTime(_ time: String) {
        timeString = time
    }
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: fixedWidth, height: 20)
    }
    
    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Background pill: #767680 at 60% opacity
        let backgroundRect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        let radius = bounds.height / 2
        let backgroundColor = NSColor(red: 0x76/255.0, green: 0x76/255.0, blue: 0x80/255.0, alpha: 0.60)
        let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: radius, yRadius: radius)
        backgroundColor.setFill()
        backgroundPath.fill()
        
        // Draw the time text with SF Pro font using tabular numbers (monospaced digits)
        // Tabular numbers ensure each digit takes the same width to prevent shifting
        let baseFont = NSFont(name: ".SF Pro Text", size: 13) 
            ?? NSFont(name: "SF Pro Text", size: 13)
            ?? NSFont(name: "SFProText-Regular", size: 13)
            ?? NSFont.systemFont(ofSize: 13, weight: .regular)
        
        // Get font descriptor with tabular numbers feature
        let fontDescriptor = baseFont.fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
                ]
            ]
        ])
        
        let font = NSFont(descriptor: fontDescriptor, size: 13) ?? baseFont
        let textColor = NSColor.labelColor
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let attributedString = NSAttributedString(string: timeString, attributes: attributes)
        let textSize = attributedString.size()
        
        // Center the text vertically and horizontally
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2 - 1, // Slight vertical adjustment for menu bar
            width: textSize.width,
            height: textSize.height
        )
        
        attributedString.draw(in: textRect)
    }
}

