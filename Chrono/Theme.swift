//
//  Theme.swift
//  Chrono
//
//  Created by Ivan Inozemtsev on 16.10.26.
//

import SwiftUI
import AppKit

/// Design tokens from the Chrono 2.0 Figma (`Update_V.2_(macOS 26/27)`).
/// Dark Mode matches the Figma exactly; Light Mode uses black-based text and fills.
nonisolated enum Theme {
    enum Colors {
        static let blue = Color(red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0)   // #0A84FF Start / accent
        static let orange = Color(red: 0xFF / 255.0, green: 0x9F / 255.0, blue: 0x0A / 255.0) // #FF9F0A Stop
        static let red = Color(red: 0xFF / 255.0, green: 0x45 / 255.0, blue: 0x3A / 255.0)    // #FF453A destructive

        /// Label on blue / orange / red fills — white in both appearances.
        static let onAccent = Color.white

        // Panel tint over the blur on macOS 14–15 only. On macOS 26 the panel
        // uses the system Liquid Glass untinted, like notification banners.
        static let panelFillDark = Color(red: 28 / 255.0, green: 28 / 255.0, blue: 30 / 255.0).opacity(0.72)
        static let panelFillLight = Color(red: 246 / 255.0, green: 246 / 255.0, blue: 248 / 255.0).opacity(0.70)
        static let panelBorder = adaptive(dark: .white.opacity(0.14), light: .black.opacity(0.08))
        static let panelShadow = Color.black.opacity(0.35)

        // Text and fills: white-based in Dark Mode (Figma), black-based in Light Mode.
        static let text = adaptive(dark: .white, light: .black.opacity(0.88))
        static let textHeader = adaptive(dark: .white.opacity(0.90), light: .black.opacity(0.85))
        static let textSecondary = adaptive(dark: .white.opacity(0.45), light: .black.opacity(0.50))
        static let separator = adaptive(dark: .white.opacity(0.10), light: .black.opacity(0.10))
        static let buttonNeutral = adaptive(dark: .white.opacity(0.14), light: .black.opacity(0.08))   // Reset, Cancel

        static let rowActiveFill = adaptive(dark: .white.opacity(0.14), light: .black.opacity(0.08))
        static let rowHoverFill = adaptive(dark: .white.opacity(0.07), light: .black.opacity(0.04))
        static let rowControlFill = adaptive(dark: .white.opacity(0.16), light: .black.opacity(0.08))

        static let fieldFill = adaptive(dark: .black.opacity(0.25), light: .white.opacity(0.80))

        static let confirmFill = red.opacity(0.18)
        static let confirmBorder = red.opacity(0.35)

        static let headerIcon = adaptive(dark: .white.opacity(0.90), light: .black.opacity(0.70))
        static let rowNameInactive = adaptive(dark: .white.opacity(0.88), light: .black.opacity(0.80))
        static let rowTimeActive = adaptive(dark: .white.opacity(0.90), light: .black.opacity(0.80))
        static let rowTimeInactive = adaptive(dark: .white.opacity(0.50), light: .black.opacity(0.50))
        static let liveBars = adaptive(dark: .white.opacity(0.90), light: .black.opacity(0.75))
        static let newProjectText = adaptive(dark: .white.opacity(0.75), light: .black.opacity(0.70))
        static let shortcutHint = adaptive(dark: .white.opacity(0.35), light: .black.opacity(0.40))     // "⌘N", version, Quit
        static let footerHint = adaptive(dark: .white.opacity(0.40), light: .black.opacity(0.45))       // "Return to save · Esc to cancel"
        static let bodyText = adaptive(dark: .white.opacity(0.65), light: .black.opacity(0.62))         // confirmation body, Info blurbs
        static let boxFill = adaptive(dark: .white.opacity(0.06), light: .black.opacity(0.04))          // Info shortcut box
        static let boxRowText = adaptive(dark: .white.opacity(0.85), light: .black.opacity(0.80))
        static let keycapFill = adaptive(dark: .white.opacity(0.12), light: .black.opacity(0.07))
        static let keycapText = adaptive(dark: .white.opacity(0.85), light: .black.opacity(0.75))

        /// A color that resolves per appearance (follows the panel's effective appearance).
        static func adaptive(dark: Color, light: Color) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(isDark ? dark : light)
            })
        }
    }

    enum Panel {
        static let width: CGFloat = 300
        static let cornerRadius: CGFloat = 20
        static let paddingTop: CGFloat = 12
        static let paddingHorizontal: CGFloat = 12
        static let paddingBottom: CGFloat = 10
        static let spacing: CGFloat = 10
        static let borderWidth: CGFloat = 1
        static let shadowRadius: CGFloat = 40
        static let shadowY: CGFloat = 14
    }

    enum Buttons {
        static let height: CGFloat = 38
        static let cornerRadius: CGFloat = 22
        static let spacing: CGFloat = 8
        static let fontSize: CGFloat = 13
    }

    enum Row {
        static let height: CGFloat = 32
        static let paddingHorizontal: CGFloat = 10
        static let spacing: CGFloat = 8
        static let gap: CGFloat = 2
        static let controlSize: CGFloat = 22
        static let maxVisibleRows = 8
        static let hoverTrailingPadding: CGFloat = 6
        static let fieldHeight: CGFloat = 22
        static let fieldBorderWidth: CGFloat = 2
        static let controlGlyphSize: CGFloat = 10
        static let newProjectLeadingPadding: CGFloat = 8
        /// Height of the scrolling list viewport (8 rows + 7 gaps).
        static var maxListHeight: CGFloat {
            CGFloat(maxVisibleRows) * height + CGFloat(maxVisibleRows - 1) * gap
        }
    }

    enum Confirm {
        static let cornerRadius: CGFloat = 20
        static let paddingHorizontal: CGFloat = 12
        static let paddingVertical: CGFloat = 10
        static let spacing: CGFloat = 4
        static let buttonHeight: CGFloat = 28
    }

    enum Info {
        static let sectionSpacing: CGFloat = 12
        static let boxCornerRadius: CGFloat = 10
        static let boxPaddingHorizontal: CGFloat = 10
        static let boxPaddingVertical: CGFloat = 6
        static let boxRowHeight: CGFloat = 24
        static let keycapCornerRadius: CGFloat = 5
    }

    enum Fonts {
        static let header = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let hero = SwiftUI.Font.system(size: 48, weight: .bold).monospacedDigit()
        static let heroTracking: CGFloat = -0.6
        static let sectionHeader = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let sectionHeaderTracking: CGFloat = 0.4
        static let rowName = SwiftUI.Font.system(size: 13)
        static let rowNameActive = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let rowTime = SwiftUI.Font.system(size: 12, weight: .medium).monospacedDigit()
        static let footnote = SwiftUI.Font.system(size: 11)

        // Phase 2a (UI) additions
        static let headerIconSize: CGFloat = 16
        static let button = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let sectionTotal = SwiftUI.Font.system(size: 11, weight: .medium).monospacedDigit()
        static let shortcutHint = SwiftUI.Font.system(size: 12, weight: .medium)
        static let field = SwiftUI.Font.system(size: 13)
        static let cardTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 12)
        static let keycap = SwiftUI.Font.system(size: 11, weight: .medium)
    }
}
