# Agent Execution Context: Chrono

Guidelines for maintaining and extending Chrono. Read this before changing windowing, animation, hotkeys, or menu bar behavior.

---

## Project overview

Chrono is a minimalist macOS menu bar time tracker with multiple projects. It shows a fluid status bar pill and opens a custom floating panel instead of a native `NSPopover`. This gives it macOS 26 prominent floating element styling: 20pt corners, liquid glass, and no system chrome bleed. It is distributed on the Mac App Store, with a DMG for direct builds.

**Version:** 2.0.0 (build 3) · **Bundle:** `com.inozemtsev.Chrono` · **Target:** macOS 14+ · 2.0 spec: `docs/PLAN-2.0.md`

### Core modules

| Module | Responsibility |
|--------|----------------|
| `MenuBarManager` | `NSStatusItem`, borderless `NSPanel` subclass, `onSizeChange` → top-pinned frame updates, global dismiss monitor |
| `TimerPopoverView` | Main panel: header, hero clock, controls, project list, `GlassBackground`; swaps to `InfoView` |
| `ProjectRowView` | Project row states: active, hover (▶︎ / ⋯), inline edit, delete/reset confirmation card |
| `InfoView` | Info screen: shortcuts, Smart Auto-Pause, launch-at-login toggle, version |
| `TimerStatusBarView` | Menu bar pill. Tabular digits, width stability |
| `ProjectStore` | Single source of truth: projects, active project, running state, `tick`, JSON persistence (replaces v1 `TimerViewModel`) |
| `Project` | `Codable` model (`id`, `name`, `accumulated`, `createdAt`) |
| `TimeFormat` | `clock` (pill/hero) and `duration` (list/totals) formatting |
| `Theme` | Design tokens from Figma |
| `ActivityMonitor` | Idle (`CGEventSource`) and sleep detection → `stop(creditingUntil:)` |
| `KeyboardShortcutManager` | Global hotkeys ⌘⇧S / ⌘⇧R only |
| `LaunchAtLogin` | `SMAppService.mainApp` wrapper, default off |
| `PrivacyInfo.xcprivacy` | Privacy manifest |

### Release tooling

- `scripts/archive-appstore.sh` + `scripts/ExportOptions-AppStore.plist` — App Store archive/export to `dist/appstore/`
- `scripts/build-dmg.sh` — Release `.app` → `dist/Chrono-<version>.dmg` (direct distribution, unsigned)
- `scripts/build-icns.sh` — PNG slices in `Chrono/assets/icons/` → `build/Chrono.icns`
- App Store process: `docs/APP_STORE_CHECKLIST.md`, `docs/APP_STORE_METADATA.md`, `docs/PRIVACY.md`

---

## 1. AppKit foundation over default elements

- Chrono intentionally bypasses standard macOS `NSPopover` and system window chrome.
- It uses a manually positioned borderless `NSPanel` for true **macOS 26 prominent floating elements** layout.
- Do **not** refactor the popover back into `NSPopover` or `.popover(isPresented:)`. That breaks aesthetics and clipping.

---

## 2. Windowing and resizing (2.0 rules)

- The panel is an `NSPanel` **subclass that overrides `canBecomeKey` → `true`**. Inline text fields (new/rename) need this, and so do panel-local shortcuts.
- **The window does not resize during transitions.** While open, the panel window is a fixed, tall, fully transparent canvas (`MenuBarManager.Layout.windowHeight`, clamped to the screen) with its **top edge pinned** under the status item. Resizing the window in the same frame as a content change made the window server present the new content and the new frame in different frames, so the whole panel jumped up (rounded top corners clipped) and slid back.
- **Smooth bottom edge:** SwiftUI animates only the visible chrome height (`chromeHeight` in `TimerPopoverView.handleContentSize`, 0.25 s easeInOut). In-screen content changes animate with the same curve (`.animation(_:value: mode)` on `mainScreen`), so rows below a confirmation card or inline field follow the edge. Never run `NSAnimationContext` frame animations.
- `onSizeChange` still reports the content size; `MenuBarManager.handleSizeChange` only grows the window (top pinned, instant) if content ever exceeds it.
- Clicks: `ignoresMouseEvents` stays at its default, so the transparent area below the panel passes clicks to the app behind (the outside-click monitor then closes the panel). Never assign `ignoresMouseEvents` (even `false` disables per-pixel click-through). The panel shape has a ~1 % fill as hit-test insurance (keep ≥ ~0.004); `ChronoPanel.sendEvent` also closes the panel if a click ever lands on the transparent canvas.
- While the chrome animates, `MenuBarManager.trackShadow(for:)` refreshes the window shadow each frame (`onResizeAnimation`).
- **Menu actions that change the panel height must run after the menu closes** (`afterMenuCloses` in `ProjectRowView.swift`). Menu actions fire inside AppKit's menu-tracking run loop; resizing the panel there makes it jump or render invisibly.
- **Info is a separate screen** that replaces the main content in the same panel. Screens swap with a short crossfade while the chrome height animates.
- Panel: width 300, corner radius **20**, tokens in `Theme`. The list scrolls after 8 rows, so the panel height is bounded.

---

## 3. Top-bar component stability

- Do **not** add `fixedSize` casually without testing `TimerStatusBarView`.
- The pill text is `TimeFormat.clock(...)`. It depends on `.monospacedDigit()` and precise sizing so the pill does not jitter left/right as digits change. Check the width at the `59:59.9` → `1:00:00` format switch.
- `MenuBarManager.resizeStatusItemToFitText()` sets the `NSStatusItem` length from measured monospaced text width.

---

## 4. Onboarding removal finality

- The previous multi-page onboarding workflow was removed intentionally.
- Do not add auto-launch splash screens or onboarding flows unless explicitly requested. Keep the app lightweight, menu-bar focused, and instantly responsive. A fresh install just seeds "My Project".

---

## 5. Hotkeys

- **Global (Carbon `RegisterEventHotKey`): only ⌘⇧S (start/stop) and ⌘⇧R (reset active).**
- Panel-local only, while the panel is key: ⌘⇧1…9, ⌘N, Return, ⌘⌫, Esc. Handle them in the panel and never register them globally.
- **Never register system-reserved or common app combos globally**: ⌘Q, ⌘W, ⌘H, ⌘M, ⌘Tab, ⌘Space, ⌘⇧3/4/5 (screenshots), ⌃⌘Q (lock), and so on. v1's global ⌘Q hijacked Quit in every app. That's an App Review risk (guideline 2.5.9) and a user-hostile bug.
- Don't use `CGEventTap` or `NSEvent.addGlobalMonitorForEvents` for key capture. They need Accessibility/Input Monitoring permission, which is a review red flag for a timer.

---

## 6. App Store constraints

- **App Sandbox stays on** (`ENABLE_APP_SANDBOX = YES`). Add no entitlements beyond what a feature strictly needs, and remove unused ones.
- **Public API only.** No private frameworks, no `IORegistry` idle hacks, no shelling out. Idle time comes from `CGEventSource.secondsSinceLastEventType`, and sleep from `NSWorkspace` notifications.
- **Auto-pause timing:** pause exactly at the idle threshold (300 s; testing override `ChronoIdleThresholdSeconds` in defaults or as a launch argument) and credit up to `lastInput + threshold` — never subtract the idle minutes, never count past them. `ActivityMonitor` schedules one-shot checks for the exact moment the threshold would be reached (≤ 30 s apart) and holds a `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)` token while the timer runs; without it App Nap deferred checks by ~10 min while the panel was closed. Don't go back to blind polling.
- **Every `ProjectStore` mutation takes a `source:`** (UI control, hotkey, system event) and logs it (`os.Logger`, subsystem `com.inozemtsev.Chrono`). Pass a meaningful source from every new call site.
- **No auto-launch without consent.** Launch at login is off by default and only the user's toggle enables it. Never install helpers, Dock icons, or files outside the container.
- **No network, analytics, or third-party SDKs** without updating `docs/PRIVACY.md`, the App Privacy answers in App Store Connect, and `PrivacyInfo.xcprivacy`.
- **Privacy manifest must list every required-reason API** used. Today that's UserDefaults `CA92.1`, SystemBootTime `35F9.1`, and FileTimestamp `C617.1`. Using a new one, such as disk space or `systemUptime`, means adding it there or the upload gets an ITMS-91053 warning.
- A **Quit** item must always stay reachable from the status item menu.
- Keep `ITSAppUsesNonExemptEncryption = NO` and `LSUIElement = YES` in the generated Info.plist.

---

## 7. Documentation and versioning

- User-facing docs live in `README.md` (overview, shortcuts, build, distribution, changelog). App Store process docs live in `docs/`.
- Follow semver: **MAJOR** for a redesign or breaking data change, **MINOR** for new features, **PATCH** for bug fixes (for example 2.0.0 → 2.0.1).
- Bump these together, every time: Xcode `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`, `scripts/build-dmg.sh` (`VERSION`, `BUILD_NUMBER`, header comment), and the `README.md` version line + changelog.
- **The build number must increase on every App Store Connect upload**, including re-uploads of the same version after a rejection.
- If the `projects.json` schema changes, keep decoding backward-compatible (optional fields or a migration). Users' tracked time must never be lost by an update.
