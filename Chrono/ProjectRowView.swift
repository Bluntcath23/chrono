//
//  ProjectRowView.swift
//  Chrono
//
//  Created by Ivan Inozemtsev on 16.10.26.
//

import SwiftUI
import AppKit

// MARK: - Project row

/// One project in the panel list: active / inactive / hover states.
/// Editing and confirmation states are separate views (`ProjectNameField`,
/// `ConfirmationCard`) that `TimerPopoverView` swaps in place of the row.
struct ProjectRowView: View {
    let name: String
    let elapsed: TimeInterval
    let isActive: Bool
    /// The timer is running on this row (implies `isActive`).
    let isRunning: Bool
    /// 1…9 for the first nine rows (⌘⇧N hint), nil otherwise.
    let shortcutNumber: Int?
    let canDelete: Bool
    /// False while another transient mode (editing / confirmation) is open:
    /// hover controls are hidden so their menu key equivalents can't fire.
    var showsHoverControls: Bool = true

    /// The argument names the trigger ("row click", "row ▶ button",
    /// "accessibility") for the store's log.
    var onSelect: (String) -> Void = { _ in }
    var onSwitchAndStart: (String) -> Void = { _ in }
    var onRename: () -> Void = {}
    var onResetTime: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var isHovered = false
    /// First pointer location seen since the hover began. The ▶︎ / ⋯ controls
    /// appear only after the pointer actually MOVES inside the row — not when
    /// the panel opens (or the Mac wakes) with the cursor already over it, so
    /// a stray wake click can't land on ▶︎ and switch projects.
    @State private var hoverOrigin: CGPoint?

    private var controlsVisible: Bool { isHovered && showsHoverControls }
    /// ▶︎ is pointless on the row that is already running.
    private var showsPlay: Bool { !isRunning }

    var body: some View {
        HStack(spacing: Theme.Row.spacing) {
            // Tap target: name + time. Controls sit outside it so that clicking
            // ⋯ doesn't also select (and pause) the row.
            HStack(spacing: Theme.Row.spacing) {
                Text(name)
                    .font(isActive ? Theme.Fonts.rowNameActive : Theme.Fonts.rowName)
                    .foregroundStyle(isActive ? Theme.Colors.text : Theme.Colors.rowNameInactive)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    // Single click selects immediately (no double-click delay);
                    // the second click of a double-click renames.
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onRename() })

                if isRunning {
                    LiveBars()
                        .accessibilityHidden(true)
                }

                Text(TimeFormat.duration(elapsed))
                    .font(Theme.Fonts.rowTime)
                    .foregroundStyle(isActive ? Theme.Colors.rowTimeActive : Theme.Colors.rowTimeInactive)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect("row click") })

            if controlsVisible {
                HStack(spacing: Theme.Row.spacing) {
                    if showsPlay {
                        RowControlButton(
                            systemImage: "play.fill",
                            alwaysFilled: true,
                            accessibilityLabel: "Switch and start \(name)",
                            action: { onSwitchAndStart("row ▶ button") }
                        )
                        .help(playHelp)
                    }
                    RowMoreMenu(
                        canDelete: canDelete,
                        accessibilityLabel: "More actions for \(name)",
                        onRename: onRename,
                        onResetTime: onResetTime,
                        onDelete: onDelete
                    )
                }
                .transition(.opacity)
            }
        }
        .padding(.leading, Theme.Row.paddingHorizontal)
        .padding(.trailing, controlsVisible ? Theme.Row.hoverTrailingPadding : Theme.Row.paddingHorizontal)
        .frame(height: Theme.Row.height)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(rowFill))
        .contentShape(Capsule())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                if let origin = hoverOrigin {
                    if !isHovered && location != origin { isHovered = true }
                } else {
                    hoverOrigin = location
                }
            case .ended:
                isHovered = false
                hoverOrigin = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chronoPanelDidClose)) { _ in
            isHovered = false
            hoverOrigin = nil
        }
        .animation(.easeOut(duration: 0.12), value: controlsVisible)
        .contextMenu {
            ProjectMenuItems(canDelete: canDelete, onRename: onRename, onResetTime: onResetTime, onDelete: onDelete)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name), \(TimeFormat.duration(elapsed))\(isRunning ? ", running" : "")")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect("accessibility") }
        .accessibilityAction(named: "Switch and start") { onSwitchAndStart("accessibility") }
        .accessibilityAction(named: "Rename") { onRename() }
        .accessibilityAction(named: "Reset Time") { onResetTime() }
        .accessibilityAction(named: "Delete Project") { if canDelete { onDelete() } }
    }

    private var rowFill: Color {
        if isActive { return Theme.Colors.rowActiveFill }
        if controlsVisible { return Theme.Colors.rowHoverFill }
        return .clear
    }

    private var playHelp: String {
        guard let number = shortcutNumber else { return "Switch & start" }
        return "Switch & start ⌘⇧\(number)"
    }
}

// MARK: - Menu items (shared by right-click and ⋯)

/// Runs `action` once the menu has fully closed. Menu actions fire inside
/// AppKit's menu-tracking run loop; if the panel resizes there (Delete / Reset
/// confirmation cards make it taller), it renders at the wrong position or not
/// at all. `.default` mode blocks only run after tracking has ended.
@MainActor func afterMenuCloses(_ action: @escaping () -> Void) {
    nonisolated(unsafe) let action = action
    RunLoop.main.perform(inModes: [.default]) {
        MainActor.assumeIsolated { action() }
    }
    // `perform` queues the block without waking the run loop.
    CFRunLoopWakeUp(CFRunLoopGetMain())
}

struct ProjectMenuItems: View {
    let canDelete: Bool
    let onRename: () -> Void
    let onResetTime: () -> Void
    let onDelete: () -> Void

    var body: some View {
        // The shortcuts are display hints: the panel's key monitor consumes
        // Return / ⌘⌫ before AppKit looks for menu key equivalents.
        Button("Rename") { afterMenuCloses(onRename) }
            .keyboardShortcut(.return, modifiers: [])
        Button("Reset Time…") { afterMenuCloses(onResetTime) }
        Divider()
        Button("Delete Project…", role: .destructive) { afterMenuCloses(onDelete) }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!canDelete)
    }
}

/// ⋯ button that opens the same native menu as right-click.
private struct RowMoreMenu: View {
    let canDelete: Bool
    let accessibilityLabel: String
    let onRename: () -> Void
    let onResetTime: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Menu {
            ProjectMenuItems(canDelete: canDelete, onRename: onRename, onResetTime: onResetTime, onDelete: onDelete)
        } label: {
            RowControlGlyph(systemImage: "ellipsis", filled: isHovered)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

/// 22 pt circular control (▶︎).
private struct RowControlButton: View {
    let systemImage: String
    var alwaysFilled: Bool = false
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            RowControlGlyph(systemImage: systemImage, filled: alwaysFilled || isHovered)
                .brightness(isHovered ? 0.08 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct RowControlGlyph: View {
    let systemImage: String
    let filled: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: Theme.Row.controlGlyphSize, weight: .bold))
            .foregroundStyle(Theme.Colors.text)
            .frame(width: Theme.Row.controlSize, height: Theme.Row.controlSize)
            .background(Circle().fill(filled ? Theme.Colors.rowControlFill : .clear))
            .contentShape(Circle())
    }
}

// MARK: - Live indicator

/// Three small bars that gently "breathe" while the timer runs.
struct LiveBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let baseHeights: [CGFloat] = [5, 9, 6]
    private static let barWidth: CGFloat = 2
    private static let spacing: CGFloat = 2
    private static let maxHeight: CGFloat = 10

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: Self.spacing) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Theme.Colors.liveBars)
                        .frame(width: Self.barWidth, height: height(index: index, time: t))
                }
            }
            .frame(height: Self.maxHeight, alignment: .bottom)
        }
    }

    private func height(index: Int, time: TimeInterval) -> CGFloat {
        let base = Self.baseHeights[index]
        guard !reduceMotion else { return base }
        let speeds: [Double] = [3.1, 2.3, 3.7]
        let phases: [Double] = [0, 1.7, 3.3]
        let wave = sin(time * speeds[index] + phases[index])   // -1…1
        return min(Self.maxHeight, max(3, base + CGFloat(wave) * 2.5))
    }
}

// MARK: - Inline name field (new project / rename)

/// Capsule text field with a 2 px blue border and a blue ✓ button.
/// Return saves, Esc cancels (handled by the panel key monitor), an empty
/// name is never saved.
struct ProjectNameField: View {
    @Binding var text: String
    var placeholder: String = "Project name"
    let onCommit: () -> Void
    /// Called when the field loses focus without Return / ✓.
    let onBlur: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Row.spacing) {
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.Colors.footerHint))
                .textFieldStyle(.plain)
                .font(Theme.Fonts.field)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .focused($isFocused)
                .onSubmit(onCommit)
                .padding(.horizontal, 8)
                .frame(height: Theme.Row.fieldHeight)
                .background(Capsule().fill(Theme.Colors.fieldFill))
                .overlay(Capsule().strokeBorder(Theme.Colors.blue, lineWidth: Theme.Row.fieldBorderWidth))
                .accessibilityLabel("Project name")

            Button(action: onCommit) {
                Image(systemName: "checkmark")
                    .font(.system(size: Theme.Row.controlGlyphSize, weight: .bold))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(width: Theme.Row.controlSize, height: Theme.Row.controlSize)
                    .background(Circle().fill(Theme.Colors.blue))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save name")
        }
        .padding(.leading, Theme.Row.paddingHorizontal)
        .padding(.trailing, Theme.Row.hoverTrailingPadding)
        .frame(height: Theme.Row.height)
        .onAppear {
            // Wait one runloop turn so the field is in the (key) window.
            DispatchQueue.main.async { isFocused = true }
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused && !focused { onBlur() }
        }
    }
}

// MARK: - Inline confirmation card (Delete / Reset Time)

struct ConfirmationCard: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Confirm.spacing) {
            Text(title)
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Buttons.spacing) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(PillButtonStyle(fill: Theme.Colors.buttonNeutral, height: Theme.Confirm.buttonHeight, label: Theme.Colors.text))
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(PillButtonStyle(fill: Theme.Colors.red, height: Theme.Confirm.buttonHeight))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, Theme.Confirm.paddingHorizontal)
        .padding(.vertical, Theme.Confirm.paddingVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Confirm.cornerRadius, style: .continuous)
                .fill(Theme.Colors.confirmFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Confirm.cornerRadius, style: .continuous)
                .strokeBorder(Theme.Colors.confirmBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Pill button style (Start / Stop / Reset / Cancel / Delete)

struct PillButtonStyle: ButtonStyle {
    let fill: Color
    var height: CGFloat = Theme.Buttons.height
    /// White on accent fills; pass `Theme.Colors.text` for neutral buttons.
    var label: Color = Theme.Colors.onAccent

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, fill: fill, height: height, label: label)
    }

    private struct PillButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let fill: Color
        let height: CGFloat
        let label: Color
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.Fonts.button)
                .foregroundStyle(label)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Capsule().fill(fill))
                .brightness(configuration.isPressed ? -0.08 : (isHovered ? 0.05 : 0))
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Capsule())
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovered)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Rows") {
    VStack(spacing: Theme.Row.gap) {
        ProjectRowView(name: "Chrono Update", elapsed: 5106, isActive: true, isRunning: true, shortcutNumber: 1, canDelete: true)
        ProjectRowView(name: "Client Website", elapsed: 22320, isActive: false, isRunning: false, shortcutNumber: 2, canDelete: true)
        ProjectNameField(text: .constant("Packaging Design"), onCommit: {}, onBlur: {})
        ConfirmationCard(
            title: "Delete “Branding”?",
            message: "2h 04m of tracked time will be removed. This can’t be undone.",
            confirmTitle: "Delete",
            onCancel: {}, onConfirm: {}
        )
    }
    .padding(12)
    .frame(width: Theme.Panel.width)
    .background(Color(white: 0.35))
}
#endif
