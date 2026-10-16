# Chrono 2.0 — Implementation Plan

Source design: Figma `Chrono_App` → page `Update_V.2_(macOS 26/27)` (node 8:5).
Branch: `feature/chrono-2.0`. Target version: **2.0.0 (build 3)**.

## Product decisions (confirmed with owner)

- Multiple projects; each keeps its own cumulative time (no daily reset).
- Exactly one project is **active**; at most one timer runs (always the active one).
- Click a row → make it active (pauses the running timer). ▶︎ on a row → switch and start.
- **No "Change Color"** in 2.0 (mockups omit it).
- Global hotkeys: **⌘⇧S** start/stop, **⌘⇧R** reset active. Nothing else is global.
  **The v1 global ⌘Q hotkey must be removed** (it hijacks ⌘Q in every app).
- **⌘⇧1…9, ⌘N, Return, ⌘⌫, Esc are panel-local** (they work only while the panel is key).
- **Launch at login** toggle in the Info view (SMAppService, default off).
- Distribution: Mac App Store (free). Keep the DMG script working for direct builds.
- Last project cannot be deleted. Deleting the active project stops the timer and activates the project above it (or the next one if it was first).
- Fresh install seeds one project named **"My Project"**.

## Phases & ownership

| Phase | Agent | Owns (exclusive write access) |
|---|---|---|
| 1 | Foundation | `Project.swift`, `ProjectStore.swift`, `TimeFormat.swift`, `Theme.swift` (tokens), pbxproj file registration, deletes `TimerViewModel.swift`, temporary compile shims |
| 2a | UI | `TimerPopoverView.swift`, `ProjectRowView.swift`, `InfoView.swift`, `Theme.swift` (may extend) |
| 2b | Platform | `MenuBarManager.swift`, `TimerStatusBarView.swift`, `KeyboardShortcutManager.swift`, `ActivityMonitor.swift`, `ChronoApp.swift`, `LaunchAtLogin.swift`, `PrivacyInfo.xcprivacy`, pbxproj build settings |
| 2c | Release docs | `README.md`, `AGENTS.md`, `scripts/*`, `docs/APP_STORE_CHECKLIST.md`, `docs/PRIVACY.md`, `docs/APP_STORE_METADATA.md` |
| 3 | Lead (review) | Integration fixes, final build, review |

Phase 2a/2b/2c run in parallel and must not edit each other's files.

## Shared API contract (Phase 1 delivers exactly this)

```swift
struct Project: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var accumulated: TimeInterval   // finished sessions only
    var createdAt: Date
}

@MainActor final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project]
    @Published private(set) var activeProjectID: UUID
    @Published private(set) var isRunning: Bool
    @Published private(set) var tick: Date          // updated every 0.1 s while running; drives UI refresh

    var activeProject: Project { get }
    var activeElapsed: TimeInterval { get }          // includes the live segment
    var totalElapsed: TimeInterval { get }           // all projects, includes live segment
    var canDelete: Bool { get }                      // projects.count > 1
    func elapsed(for id: UUID) -> TimeInterval
    func index(of id: UUID) -> Int?

    func start()
    func stop()                                      // credits time up to now
    func stop(creditingUntil date: Date)             // used by auto-pause: drop idle time
    func toggle()
    func resetActive()
    func resetTime(for id: UUID)                     // if running on that project, keeps running from 0
    func select(_ id: UUID)                          // make active; pauses timer if running another project
    func switchAndStart(_ id: UUID)
    func switchAndStart(index: Int)                  // 0-based; out of range = no-op
    @discardableResult func addProject(named: String) -> Project?   // trimmed; empty → nil; appended at the end; does NOT change the active project
    func rename(_ id: UUID, to name: String)         // trimmed; empty → ignored
    func delete(_ id: UUID)                          // no-op when !canDelete
    func flush()                                     // synchronous save (call on terminate)
}

enum TimeFormat {
    static func clock(_ t: TimeInterval) -> String    // < 1h: "04:12.6"   ≥ 1h: "1:25:06"
    static func duration(_ t: TimeInterval) -> String // "1h 25m", "0h 40m", "10h 21m"
}
```

Persistence: JSON at `Application Support/Chrono/projects.json` (sandbox container), atomic writes, saved on every mutation and every 30 s while running. The running session start (`runningSince`) and `lastCheckpoint` are persisted so that after a crash the time up to the last checkpoint is credited and the timer comes back paused.

## Design tokens (from Figma)

- Panel: width **300**, corner radius **20**, padding 12 (top) / 12 (sides) / 10 (bottom), vertical spacing 10, 1 px border white 14 %, shadow 0 14 40 black 35 %.
  - macOS 26: untinted system Liquid Glass (`.glassEffect(.regular)`), matching notification banners (owner feedback). macOS 14–15: blur + dark rgba(28,28,30,0.72) / light rgba(246,246,248,0.70) tint and 1 px border. Text is white in Dark Mode and dark in Light Mode (owner feedback after first test).
- Header: active project name, 13 semibold, white 90 %, centered; info icon 16 pt at right, 90 % opacity.
- Hero clock: 48 bold, tracking −0.6, tabular digits, white.
- Buttons: h 38, capsule (r 22), 13 semibold white. Start #0A84FF · Stop #FF9F0A · Reset white 14 %. Two equal-width buttons, 8 apart.
- Separator: 1 px white 10 %.
- Section header: "PROJECTS" 11 semibold tracking 0.4, "Total 10h 21m" 11 medium; both white 45 %; padding h 10, top 2.
- Project row: h 32, padding h 10, spacing 8, rows 2 apart.
  - Active: capsule fill white 14 %, name 13 semibold white, time 12 medium white 90 %, live bars (3 bars 2 px wide, heights 5/9/6, white 90 %, 2 apart) only while running.
  - Inactive: name 13 regular white 88 %, time 12 medium white 50 %.
  - Hover (inactive): capsule fill white 7 %, trailing padding 6, shows ▶︎ (22 pt circle, white 16 %, 10 pt glyph) and ⋯ (22 pt circle, fill white 16 % on hover). Tooltip on ▶︎: "Switch & start ⌘⇧N" (N = row index + 1, for rows 1–9).
- Inline field (new/rename): h 22, capsule, fill black 25 %, 2 px border #0A84FF, 13 regular white; confirm button 22 pt circle #0A84FF with checkmark. While editing, the footer reads "Return to save · Esc to cancel" (11 regular white 40 %, centered) in place of the New Project row.
- New Project row: h 32, padding l 8 r 10, plus glyph 12 pt at 75 %, "New Project" 13 regular white 75 %, "⌘N" 12 medium white 35 %.
- Context menu (right-click or ⋯): Rename (Return) · Reset Time… · — · Delete Project… (⌘⌫, destructive, disabled for the last project). Use the native menu.
- Inline confirmation card (replaces the row): fill rgba(255,69,58,0.18), 1 px border rgba(255,69,58,0.35), r 20, padding 12/10, spacing 4. Title 13 semibold white `Delete “Branding”?`; body 12 white 65 % `2h 04m of tracked time will be removed. This can’t be undone.`; buttons h 28 r 14: Cancel (white 14 %) / Delete (#FF453A). Reset Time… uses the same card: `Reset “Branding”?` / `2h 04m of tracked time will be cleared.` / Cancel · Reset.
- Info view (replaces the main content; no expansion): header "Chrono" left (13 semibold white 90 %), "Done" right (#0A84FF). Sections: "Projects" + body; KEYBOARD SHORTCUTS box (fill white 6 %, r 10, padding 10/6, rows h 24, 12 regular white 85 %, keycaps 11 medium on white 12 % r 5 padding 6/2); "Smart Auto-Pause" + body; Launch at login toggle; "Version x.y" 11 regular white 35 % centered (read from the bundle).
- Many projects: the list scrolls after 8 rows.
- Menu bar pill: 13 medium tabular digits, h 22, padding h 8, capsule fill primary 15 % (24 % while the panel is open); text primary 100 % while running, 75 % while paused. Format = `TimeFormat.clock`.
- Notification: title "Chrono", body `<Project> paused — away for 5 min` (idle) / `<Project> paused — Mac went to sleep` (sleep).

## Windowing rules (still apply; see AGENTS.md)

- Borderless `NSPanel` subclass that overrides `canBecomeKey = true` (needed for text fields).
- Top edge pinned on every resize; one `setFrame(animate: false)` per state change. **Do not animate heights inside SwiftUI**; use opacity/crossfade transitions only so AppKit and SwiftUI never run competing animations.
- The v1 mask expansion machinery is removed (Info is now a separate screen).

## Phase 2 interface (frozen — 2a and 2b both depend on it)

```swift
// TimerPopoverView.swift (owned by 2a; keep this exact memberwise shape)
struct TimerPopoverView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var launchAtLogin: LaunchAtLogin
    var onSizeChange: ((CGSize) -> Void)? = nil   // report the full panel size once per state change
    var onClose: (() -> Void)? = nil              // UI asks AppKit to hide the panel (Esc when idle)
}
extension Notification.Name { static let chronoPanelDidClose }  // defined in TimerPopoverView.swift; posted by MenuBarManager on hide

// LaunchAtLogin.swift (done by lead)
@MainActor final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled: Bool
    func refresh(); func setEnabled(_ enabled: Bool)
}
```

- 2b (MenuBarManager) guarantees: panel is key while visible (`canBecomeKey == true`), so SwiftUI focus, TextField, `.onKeyPress` and `.keyboardShortcut` work; panel hides on outside click, status item click, and `onClose`; it calls `launchAtLogin.refresh()` when the panel opens; posts `.chronoPanelDidClose` on every hide.
- 2a (UI) owns all panel-local keys: ⌘N, Return (rename active), ⌘⌫ (delete active → confirmation), Esc (cancel edit/confirmation/info; otherwise `onClose`), ⌘⇧1…9 (switch & start), ⌘Q (quit).
