//
//  TimerPopoverView.swift
//  Chrono
//
//  Created by Ivan on 15.11.25.
//

import SwiftUI
import AppKit

/// Content of Chrono's floating panel (hosted by `MenuBarManager` in a
/// borderless `NSPanel`).
///
/// Two screens, Main and Info, swapped with a short fade-out / fade-in.
///
/// Height changes (Info ↔ Main, rows added/removed, confirmations) move only
/// the bottom edge (see AGENTS.md §2): the hosting window is a fixed, tall,
/// transparent canvas that does not resize during transitions, and the visible
/// chrome (`chromeHeight`) animates in SwiftUI. Content changes inside the main
/// screen animate with the same curve, so rows follow the edge.
struct TimerPopoverView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var launchAtLogin: LaunchAtLogin
    var onSizeChange: ((CGSize) -> Void)? = nil   // report the full panel size once per state change
    var onClose: (() -> Void)? = nil              // UI asks AppKit to hide the panel (Esc when idle)
    var onResizeAnimation: ((TimeInterval) -> Void)? = nil   // chrome height is animating for this long (AppKit refreshes the window shadow)

    /// The single transient mode. Editing, confirmation and Info are mutually
    /// exclusive by construction.
    enum Mode: Equatable {
        case idle
        case editing(EditTarget)
        case confirming(Confirmation)
        case info
    }

    enum EditTarget: Equatable {
        case newProject
        case rename(UUID)
    }

    struct Confirmation: Equatable {
        enum Kind: Equatable { case delete, reset }
        let kind: Kind
        let projectID: UUID
    }

    @State private var mode: Mode = .idle
    @State private var draftName = ""
    @State private var contentOpacity: Double = 1
    /// Invalidates pending fade completions (e.g. when the panel closes mid-fade).
    @State private var transitionToken = 0
    /// Height of the visible panel chrome; animated between layouts. `nil` until first measured.
    @State private var chromeHeight: CGFloat?
    @Environment(\.colorScheme) private var colorScheme

    private static let resizeDuration: TimeInterval = 0.25
    private static let resizeAnimation = Animation.easeInOut(duration: resizeDuration)

    private static let newProjectRowID = "chrono.new-project-row"

    var body: some View {
        content
            .opacity(contentOpacity)
            .padding(.top, Theme.Panel.paddingTop)
            .padding(.horizontal, Theme.Panel.paddingHorizontal)
            .padding(.bottom, Theme.Panel.paddingBottom)
            .frame(width: Theme.Panel.width)
            .fixedSize(horizontal: false, vertical: true)
            .background(sizeReporter)
            // The chrome follows `chromeHeight`, not the content, so its bottom edge can animate.
            .frame(height: chromeHeight, alignment: .top)
            .background(panelBackground)
            .clipShape(panelShape)
            .overlay(panelBorder)
            .background(PanelKeyMonitor(handler: handleKey))
            // If AppKit's frame is momentarily taller than the content, keep it top-aligned.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onReceive(NotificationCenter.default.publisher(for: .chronoPanelDidClose)) { _ in
                resetTransientState()
            }
    }

    @ViewBuilder
    private var content: some View {
        if mode == .info {
            InfoView(launchAtLogin: launchAtLogin, onDone: { setMode(.idle) }, onClose: onClose)
        } else {
            mainScreen
        }
    }

    // MARK: - Chrome

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Panel.cornerRadius, style: .continuous)
    }

    /// macOS 26: the system Liquid Glass alone — the same material and edge
    /// highlight as notification banners, adapting to Light/Dark. Earlier
    /// macOS: blur + the appearance-specific tint from the plan.
    /// Shadow comes from the NSPanel (`hasShadow`), so none is drawn here.
    private var panelBackground: some View {
        ZStack {
            // Insurance: the window server hit-tests non-opaque windows per pixel
            // (alpha byte > 0); the transparent canvas below the panel lets clicks
            // through. Liquid Glass is already hit-testable on macOS 26. Keep ≥ ~0.004.
            panelShape.fill(Color.black.opacity(0.01))
            if #available(macOS 26, *) {
                Color.clear.glassEffect(.regular, in: panelShape)
            } else {
                GlassBackground()
                panelShape.fill(colorScheme == .dark ? Theme.Colors.panelFillDark : Theme.Colors.panelFillLight)
            }
        }
    }

    /// Glass draws its own rim on macOS 26; earlier versions get the Figma border.
    @ViewBuilder
    private var panelBorder: some View {
        if #available(macOS 26, *) {
            EmptyView()
        } else {
            panelShape.strokeBorder(Theme.Colors.panelBorder, lineWidth: Theme.Panel.borderWidth)
        }
    }

    private var sizeReporter: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { handleContentSize(geo.size) }
                .onChange(of: geo.size) { _, newSize in handleContentSize(newSize) }
        }
    }

    /// Animates the visible chrome to the new content height (see type docs).
    private func handleContentSize(_ size: CGSize) {
        guard size.height > 0, size.height.isFinite else { return }

        // First layout, or the panel is hidden: apply instantly.
        guard let current = chromeHeight, Self.isPanelVisible else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { chromeHeight = size.height }
            onSizeChange?(size)
            return
        }
        guard abs(size.height - current) >= 0.5 else { return }

        // No-op for AppKit unless the content outgrows the fixed window.
        resizeWindow(to: size)
        withAnimation(Self.resizeAnimation) { chromeHeight = size.height }
        onResizeAnimation?(Self.resizeDuration)
    }

    /// Hands the size to AppKit outside any running SwiftUI animation (this is
    /// often called from inside an animated transaction, e.g. a mode change
    /// animated by `.animation(_:value: mode)`), so a rare window grow is instant.
    private func resizeWindow(to size: CGSize) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { onSizeChange?(size) }
    }

    private static var isPanelVisible: Bool {
        NSApp.windows.contains { $0 is ChronoPanel && $0.isVisible }
    }

    // MARK: - Main screen

    private var mainScreen: some View {
        VStack(spacing: Theme.Panel.spacing) {
            header
            heroClock
            controls
            Separator()
            sectionHeader
            projectList
            Separator()
            footer
        }
        // In-screen layout changes (confirmation card, inline field, rows added
        // or removed together with a mode change) animate with the same curve as
        // the chrome's bottom edge, so content and edge move together. SwiftUI
        // reports the final size once, so AppKit still gets a single resize.
        .animation(Self.resizeAnimation, value: mode)
    }

    private var header: some View {
        ZStack {
            Text(store.activeProject.name)
                .font(Theme.Fonts.header)
                .foregroundStyle(Theme.Colors.textHeader)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, Theme.Fonts.headerIconSize + 12)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Spacer()
                InfoButton { setMode(.info) }
            }
        }
        .frame(height: Theme.Fonts.headerIconSize)
    }

    private var heroClock: some View {
        Text(TimeFormat.clock(store.activeElapsed))
            .font(Theme.Fonts.hero)
            .tracking(Theme.Fonts.heroTracking)
            .foregroundStyle(Theme.Colors.text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Elapsed time")
            .accessibilityValue(TimeFormat.clock(store.activeElapsed))
    }

    private var controls: some View {
        HStack(spacing: Theme.Buttons.spacing) {
            Button(store.isRunning ? "Stop" : "Start") {
                endTransientMode()
                store.toggle(source: "Start/Stop button")
            }
            .buttonStyle(PillButtonStyle(fill: store.isRunning ? Theme.Colors.orange : Theme.Colors.blue))
            .help("Start / Stop ⌘⇧S")

            Button("Reset") {
                endTransientMode()
                store.resetActive(source: "Reset button")
            }
            .buttonStyle(PillButtonStyle(fill: Theme.Colors.buttonNeutral, label: Theme.Colors.text))
            .help("Reset current project ⌘⇧R")
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("PROJECTS")
                .font(Theme.Fonts.sectionHeader)
                .tracking(Theme.Fonts.sectionHeaderTracking)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text("Total \(TimeFormat.duration(store.totalElapsed))")
                .font(Theme.Fonts.sectionTotal)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, Theme.Row.paddingHorizontal)
        .padding(.top, 2)
    }

    // MARK: - Project list

    private var listItemCount: Int {
        store.projects.count + (mode == .editing(.newProject) ? 1 : 0)
    }

    private var projectList: some View {
        ScrollViewReader { proxy in
            Group {
                if listItemCount > Theme.Row.maxVisibleRows {
                    ScrollView(.vertical) {
                        listRows
                    }
                    .scrollIndicators(.automatic)
                    .frame(height: Theme.Row.maxListHeight)
                } else {
                    listRows
                }
            }
            .onChange(of: mode) { _, newMode in
                scrollIfNeeded(for: newMode, proxy: proxy)
            }
        }
    }

    private var listRows: some View {
        VStack(spacing: Theme.Row.gap) {
            ForEach(Array(store.projects.enumerated()), id: \.element.id) { index, project in
                row(for: project, index: index)
                    .id(project.id)
            }
            if mode == .editing(.newProject) {
                ProjectNameField(
                    text: $draftName,
                    placeholder: "New Project",
                    onCommit: commitEdit,
                    onBlur: handleFieldBlur
                )
                .id(Self.newProjectRowID)
            }
        }
    }

    @ViewBuilder
    private func row(for project: Project, index: Int) -> some View {
        switch mode {
        case .editing(.rename(let id)) where id == project.id:
            ProjectNameField(
                text: $draftName,
                onCommit: commitEdit,
                onBlur: handleFieldBlur
            )
        case .confirming(let confirmation) where confirmation.projectID == project.id:
            confirmationCard(confirmation, project: project)
        default:
            ProjectRowView(
                name: project.name,
                elapsed: store.elapsed(for: project.id),
                isActive: project.id == store.activeProjectID,
                isRunning: store.isRunning && project.id == store.activeProjectID,
                shortcutNumber: index < 9 ? index + 1 : nil,
                canDelete: store.canDelete,
                showsHoverControls: mode == .idle,
                onSelect: { source in
                    endTransientMode()
                    store.select(project.id, source: source)
                },
                onSwitchAndStart: { source in
                    endTransientMode()
                    store.switchAndStart(project.id, source: source)
                },
                onRename: { beginRename(project.id) },
                onResetTime: { confirm(.reset, project.id) },
                onDelete: { confirm(.delete, project.id) }
            )
        }
    }

    private func confirmationCard(_ confirmation: Confirmation, project: Project) -> some View {
        let duration = TimeFormat.duration(store.elapsed(for: project.id))
        switch confirmation.kind {
        case .delete:
            return ConfirmationCard(
                title: "Delete “\(project.name)”?",
                message: "\(duration) of tracked time will be removed. This can’t be undone.",
                confirmTitle: "Delete",
                onCancel: { mode = .idle },
                onConfirm: {
                    mode = .idle
                    store.delete(project.id, source: "delete card")
                }
            )
        case .reset:
            return ConfirmationCard(
                title: "Reset “\(project.name)”?",
                message: "\(duration) of tracked time will be cleared.",
                confirmTitle: "Reset",
                onCancel: { mode = .idle },
                onConfirm: {
                    mode = .idle
                    store.resetTime(for: project.id, source: "reset card")
                }
            )
        }
    }

    private func scrollIfNeeded(for newMode: Mode, proxy: ScrollViewProxy) {
        let target: AnyHashable
        switch newMode {
        case .editing(.newProject): target = Self.newProjectRowID
        case .editing(.rename(let id)): target = id
        case .confirming(let confirmation): target = confirmation.projectID
        default: return
        }
        // After the new row is laid out.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(target)
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if case .editing = mode {
            Text("Return to save · Esc to cancel")
                .font(Theme.Fonts.footnote)
                .foregroundStyle(Theme.Colors.footerHint)
                .frame(maxWidth: .infinity)
        } else {
            NewProjectRow { beginNewProject() }
        }
    }

    // MARK: - Mode transitions

    /// Changes mode; crosses between Main and Info with a fade-out → swap →
    /// fade-in so only one screen is ever laid out. Within the main screen the
    /// change animates via `.animation(_:value: mode)` on `mainScreen`.
    private func setMode(_ newMode: Mode) {
        let crossesScreens = (mode == .info) != (newMode == .info)
        guard crossesScreens else {
            mode = newMode
            return
        }
        transitionToken += 1
        let token = transitionToken
        withAnimation(.easeOut(duration: 0.08)) {
            contentOpacity = 0
        } completion: {
            guard token == transitionToken else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { mode = newMode }
            withAnimation(.easeIn(duration: 0.12)) {
                contentOpacity = 1
            }
        }
    }

    private func beginNewProject() {
        draftName = ""
        setMode(.editing(.newProject))
    }

    private func beginRename(_ id: UUID) {
        guard let project = store.projects.first(where: { $0.id == id }) else { return }
        draftName = project.name
        setMode(.editing(.rename(id)))
    }

    private func confirm(_ kind: Confirmation.Kind, _ id: UUID) {
        if kind == .delete && !store.canDelete { return }
        setMode(.confirming(Confirmation(kind: kind, projectID: id)))
    }

    /// Saves a non-empty draft; an empty one is discarded. Idempotent.
    private func commitEdit() {
        guard case .editing(let target) = mode else { return }
        let name = draftName
        mode = .idle
        draftName = ""
        switch target {
        case .newProject: store.addProject(named: name, source: "new project field")
        case .rename(let id): store.rename(id, to: name, source: "rename field")
        }
    }

    private func cancelEdit() {
        guard case .editing = mode else { return }
        mode = .idle
        draftName = ""
    }

    /// Losing focus with an empty name discards the edit. A non-empty draft
    /// stays open (it is saved by Return / ✓ / clicking another control, and
    /// discarded when the panel closes) so hiding the panel never saves a
    /// half-typed name behind the user's back.
    private func handleFieldBlur() {
        if draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cancelEdit()
        }
    }

    /// Before acting on another control: commit an edit, drop a confirmation.
    private func endTransientMode() {
        switch mode {
        case .editing: commitEdit()
        case .confirming: mode = .idle
        case .idle, .info: break
        }
    }

    private func resetTransientState() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transitionToken += 1
            mode = .idle
            draftName = ""
            contentOpacity = 1
        }
    }

    // MARK: - Keyboard (panel-local)

    /// Returns true when the key was handled (the event is then swallowed).
    private func handleKey(_ event: NSEvent, isTextEditing: Bool) -> Bool {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Auto-repeat (a key held down, or a stuck key after wake) never
        // triggers panel actions; text fields still get their repeats.
        if event.isARepeat { return !isTextEditing }

        // Esc: one transient layer at a time, else close the panel.
        if event.keyCode == KeyCode.escape && flags.isEmpty {
            switch mode {
            case .editing: cancelEdit()
            case .confirming: mode = .idle
            case .info: setMode(.idle)
            case .idle: onClose?()
            }
            return true
        }

        if flags == .command && key == "q" {
            NSApp.terminate(nil)
            return true
        }

        // While typing, Return / ⌘⌫ / ⌘N etc. belong to the text field.
        if isTextEditing { return false }

        if flags == [.command, .shift], let number = KeyCode.digit(event.keyCode) {
            if mode != .info { endTransientMode() }
            store.switchAndStart(
                index: number - 1,
                source: "panel key ⌘⇧\(number) keyCode=\(event.keyCode) flags=\(event.modifierFlags.rawValue) panelKey=\(event.window?.isKeyWindow == true) visible=\(event.window?.isVisible == true)"
            )
            return true
        }

        if flags == .command && key == "n" {
            beginNewProject()
            return true
        }

        if mode == .info { return false }

        if (event.keyCode == KeyCode.returnKey || event.keyCode == KeyCode.enter) && flags.isEmpty {
            if mode == .idle { beginRename(store.activeProjectID) }
            return true
        }

        if event.keyCode == KeyCode.delete && flags == .command {
            if store.canDelete { confirm(.delete, store.activeProjectID) }
            return true
        }

        return false
    }
}

// MARK: - Key codes

private enum KeyCode {
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76
    static let escape: UInt16 = 53
    static let delete: UInt16 = 51

    /// Top-row digit keys 1…9 by key code (independent of ⇧ and layout symbols).
    private static let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    static func digit(_ keyCode: UInt16) -> Int? { digits[keyCode] }
}

// MARK: - Panel key monitor

/// Local `keyDown` monitor scoped to the hosting window. A monitor (rather than
/// `.keyboardShortcut` buttons) gives one place with explicit precedence:
/// it runs before AppKit's key-equivalent pass, so ⌘⇧1…9 match by key code
/// regardless of the shifted symbol, and typing in a text field is detected
/// via the window's field editor.
private struct PanelKeyMonitor: NSViewRepresentable {
    let handler: (NSEvent, _ isTextEditing: Bool) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.handler = handler
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        weak var view: NSView?
        var handler: ((NSEvent, Bool) -> Bool)?
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Local monitors are always called on the main thread.
                nonisolated(unsafe) let keyEvent = event
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self,
                          let window = self.view?.window,
                          keyEvent.window === window,
                          window.isVisible,
                          window.isKeyWindow,
                          let handler = self.handler
                    else { return false }
                    let isTextEditing = window.firstResponder is NSText
                    return handler(keyEvent, isTextEditing)
                }
                return handled ? nil : event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

// MARK: - Small components

private struct Separator: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

private struct InfoButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: Theme.Fonts.headerIconSize))
                .foregroundStyle(Theme.Colors.headerIcon)
                .opacity(isHovered ? 1 : 0.9)
                .frame(width: Theme.Fonts.headerIconSize, height: Theme.Fonts.headerIconSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("About Chrono")
        .accessibilityLabel("About Chrono")
    }
}

private struct NewProjectRow: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Row.spacing) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.newProjectText)
                Text("New Project")
                    .font(Theme.Fonts.rowName)
                    .foregroundStyle(Theme.Colors.newProjectText)
                Spacer(minLength: 8)
                Text("⌘N")
                    .font(Theme.Fonts.shortcutHint)
                    .foregroundStyle(Theme.Colors.shortcutHint)
                    .accessibilityHidden(true)
            }
            .padding(.leading, Theme.Row.newProjectLeadingPadding)
            .padding(.trailing, Theme.Row.paddingHorizontal)
            .frame(height: Theme.Row.height)
            .background(Capsule().fill(isHovered ? Theme.Colors.rowHoverFill : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel("New Project")
    }
}

// MARK: - Glass background (pre-macOS 26)

struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.state = .active
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.isEmphasized = true
    }
}

// MARK: - Panel lifecycle

extension Notification.Name {
    /// Posted by `MenuBarManager` whenever the panel is hidden; the popover resets
    /// transient UI state (editing, confirmations, Info screen).
    static let chronoPanelDidClose = Notification.Name("ChronoPanelDidClose")
}

// MARK: - Previews

#if DEBUG
extension TimerPopoverView {
    /// Previews / offscreen renders only: start in a given transient mode.
    init(store: ProjectStore, launchAtLogin: LaunchAtLogin, initialMode: Mode, draftName: String = "") {
        self.store = store
        self.launchAtLogin = launchAtLogin
        self._mode = State(initialValue: initialMode)
        self._draftName = State(initialValue: draftName)
    }
}

@MainActor
enum PreviewData {
    /// A store backed by a throwaway file so previews never touch real data.
    static func store(running: Bool) -> ProjectStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chrono-preview-\(UUID().uuidString).json")
        let store = ProjectStore(storageURL: url)
        store.rename(store.activeProjectID, to: "Chrono Update")
        store.addProject(named: "Client Website")
        store.addProject(named: "Branding")
        store.addProject(named: "Reading")
        if running { store.start() }
        return store
    }
}

#Preview("Main · running") {
    TimerPopoverView(store: PreviewData.store(running: true), launchAtLogin: LaunchAtLogin())
}

#Preview("Main · paused") {
    TimerPopoverView(store: PreviewData.store(running: false), launchAtLogin: LaunchAtLogin())
}

#Preview("New project") {
    TimerPopoverView(
        store: PreviewData.store(running: true),
        launchAtLogin: LaunchAtLogin(),
        initialMode: .editing(.newProject),
        draftName: "Packaging Design"
    )
}

#Preview("Delete confirmation") {
    let store = PreviewData.store(running: true)
    return TimerPopoverView(
        store: store,
        launchAtLogin: LaunchAtLogin(),
        initialMode: .confirming(.init(kind: .delete, projectID: store.projects[2].id))
    )
}

#Preview("Info") {
    TimerPopoverView(store: PreviewData.store(running: false), launchAtLogin: LaunchAtLogin(), initialMode: .info)
}
#endif
