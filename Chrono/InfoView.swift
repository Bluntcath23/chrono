//
//  InfoView.swift
//  Chrono
//
//  Created by Ivan Inozemtsev on 16.10.26.
//

import SwiftUI
import AppKit

/// Info screen: replaces the main panel content (no expansion animation).
struct InfoView: View {
    @ObservedObject var launchAtLogin: LaunchAtLogin
    let onDone: () -> Void
    /// Asks AppKit to hide the panel (after opening the privacy policy).
    var onClose: (() -> Void)? = nil

    /// In-app privacy policy link (App Store guideline 5.1.1(i)).
    static let privacyPolicyURL = URL(string: "https://bluntcath23.github.io/chrono/PRIVACY")!

    private struct Shortcut: Identifiable {
        let title: String
        let keys: String
        var id: String { title }
    }

    private static let shortcuts: [Shortcut] = [
        Shortcut(title: "Start / Stop", keys: "⌘⇧S"),
        Shortcut(title: "Reset current project", keys: "⌘⇧R"),
        Shortcut(title: "Switch to project 1–9", keys: "⌘⇧1…9"),
        Shortcut(title: "New project", keys: "⌘N"),
        Shortcut(title: "Rename selected", keys: "Return"),
        Shortcut(title: "Delete selected", keys: "⌘⌫"),
    ]

    private var versionString: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Info.sectionSpacing) {
            header

            section(
                title: "Projects",
                body: "Keep a separate timer for every project. Only one runs at a time — switching pauses the current one."
            )

            shortcutsBox

            section(
                title: "Smart Auto-Pause",
                body: "The running project pauses when you’re away or your Mac sleeps — you’ll get a notification telling you which one."
            )

            launchAtLoginRow

            footer
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            Text("Chrono")
                .font(Theme.Fonts.header)
                .foregroundStyle(Theme.Colors.textHeader)
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.plain)
                .font(Theme.Fonts.header)
                .foregroundStyle(Theme.Colors.blue)
                .help("Done (Esc)")
        }
        .frame(height: Theme.Fonts.headerIconSize)
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Fonts.header)
                .foregroundStyle(Theme.Colors.text)
            Text(body)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var shortcutsBox: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("KEYBOARD SHORTCUTS")
                .font(Theme.Fonts.sectionHeader)
                .tracking(Theme.Fonts.sectionHeaderTracking)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityAddTraits(.isHeader)

            ForEach(Self.shortcuts) { shortcut in
                HStack {
                    Text(shortcut.title)
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.Colors.boxRowText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Keycap(text: shortcut.keys)
                }
                .frame(height: Theme.Info.boxRowHeight)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, Theme.Info.boxPaddingHorizontal)
        .padding(.vertical, Theme.Info.boxPaddingVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Info.boxCornerRadius, style: .continuous)
                .fill(Theme.Colors.boxFill)
        )
    }

    private var launchAtLoginRow: some View {
        HStack {
            Text("Launch at login")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.boxRowText)
            Spacer(minLength: 8)
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .tint(Theme.Colors.blue)
        }
        .padding(.horizontal, Theme.Info.boxPaddingHorizontal)
        .frame(height: Theme.Row.height)
        .background(
            RoundedRectangle(cornerRadius: Theme.Info.boxCornerRadius, style: .continuous)
                .fill(Theme.Colors.boxFill)
        )
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let versionString {
                Text("Version \(versionString)")
            }
            HStack(spacing: 0) {
                Button("Privacy Policy") {
                    NSWorkspace.shared.open(Self.privacyPolicyURL)
                    onClose?()
                }
                .buttonStyle(.plain)
                .help(Self.privacyPolicyURL.absoluteString)

                Text(" · ")
                    .accessibilityHidden(true)

                Button("Quit Chrono") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .help("Quit Chrono (⌘Q)")
            }
        }
        .font(Theme.Fonts.footnote)
        .foregroundStyle(Theme.Colors.shortcutHint)
        .frame(maxWidth: .infinity)
    }
}

/// Small rounded key label, e.g. "⌘⇧S".
struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Fonts.keycap)
            .foregroundStyle(Theme.Colors.keycapText)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Info.keycapCornerRadius, style: .continuous)
                    .fill(Theme.Colors.keycapFill)
            )
    }
}
