# Chrono

Chrono is your minimalist and lightweight macOS menu bar timer built for tracking time and staying focused. It’s designed to stay out of your way while you work — with a clean interface, quick access via hotkeys, and a subtle always-on-top presence that makes time tracking feel effortless.

**Current version:** 2.0.0

## Preview

<p align="center">
  <img src="https://tojp4f5baeta7girwrpqvogul40oddhk.lambda-url.eu-central-1.on.aws/img/in-next-app/chrono-01.jpg?w=3840&q=75&f=webp" alt="Chrono app icon" width="360" />
  &nbsp;&nbsp;
  <img src="https://tojp4f5baeta7girwrpqvogul40oddhk.lambda-url.eu-central-1.on.aws/img/in-next-app/chrono-02.jpg?w=3840&q=75&f=webp" alt="Chrono menu bar pill and floating timer panel" width="360" />
</p>

<p align="center"><em>App icon · Menu bar timer with liquid glass floating panel</em></p>

---

## Overview

Chrono lives in the menu bar as a compact time pill. Click it to open a borderless floating glass panel: the active project's clock, Start/Stop and Reset, and your project list with a running total. Info (shortcuts, auto-pause, launch at login) is a separate screen inside the same panel.

The app deliberately avoids standard `NSPopover` chrome. A custom `NSPanel` (`MenuBarManager`) is sized by SwiftUI with the top edge pinned under the pill, one frame update per state change.

### Features

- **Projects** — Unlimited projects, each with its own cumulative time; one active project, at most one running timer
- **Fast switching** — Click a row to make it active, ▶︎ to switch & start, ⌘⇧1…9 while the panel is open
- **Inline editing** — New / rename in place; Reset Time… and Delete Project… confirm with an inline card (last project can't be deleted)
- **Smart auto-pause** — Pauses the active project after 5 min idle or when the Mac sleeps; idle time is not counted; local notification
- **Persistence** — Projects and times saved locally (JSON in the sandbox container), crash-safe checkpoints every 30 s
- **Liquid glass UI** — 300 pt panel, 20 pt corners, white text in light and dark appearance
- **Stable menu bar pill** — Tabular monospaced digits; width doesn't jitter as time changes
- **Launch at login** — Optional (SMAppService), off by default
- **Private** — No network, no analytics, no account ([privacy policy](docs/PRIVACY.md))

### Keyboard shortcuts

| Shortcut | Action | Scope |
|----------|--------|-------|
| ⌘⇧S | Start / stop active project | **Global** |
| ⌘⇧R | Reset active project | **Global** |
| ⌘⇧1…9 | Switch to project N and start | Panel open |
| ⌘N | New project | Panel open |
| Return | Rename selected / save edit | Panel open |
| ⌘⌫ | Delete project… | Panel open |
| Esc | Cancel edit / close | Panel open |
| ⌘Q | Quit Chrono | Panel open |

Only ⌘⇧S and ⌘⇧R are registered system-wide. Chrono never captures ⌘Q (or any other shortcut) system-wide. You can also quit from the right-click menu on the menu bar pill, or from the Info screen.

---

## Requirements

- macOS 14+
- Xcode 26 / Swift 5.9+

---

## Quick start

### Open in Xcode

```bash
open Chrono.xcodeproj
```

### Clean build (Debug)

From the project root:

```bash
rm -rf .DerivedData
xcodebuild -scheme Chrono \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .DerivedData \
  build
open .DerivedData/Build/Products/Debug/Chrono.app
```

### Release build

```bash
xcodebuild -scheme Chrono \
  -configuration Release \
  -destination 'platform=macOS' \
  build
```

---

## Distribution

### Mac App Store

```bash
bash scripts/archive-appstore.sh
```

Archives a signed Release build to `build/Chrono.xcarchive` and exports it with `scripts/ExportOptions-AppStore.plist` to `dist/appstore/` (switch `destination` to `upload` to send it straight to App Store Connect). Requires an Apple Developer Program membership and `DEVELOPMENT_TEAM` set on the target — the script stops early if it isn't.

Full walkthrough (enrollment → review → release): [`docs/APP_STORE_CHECKLIST.md`](docs/APP_STORE_CHECKLIST.md) · store copy: [`docs/APP_STORE_METADATA.md`](docs/APP_STORE_METADATA.md).

### Direct download (DMG)

The DMG pipeline builds icons, compiles a Release `.app`, stages a styled disk image, and writes the final artifact to `dist/`.

```bash
bash scripts/build-dmg.sh
```

**Output:** `dist/Chrono-2.0.0.dmg`

The script runs six steps: preflight → `.icns` → Release `.app` → DMG staging → Finder cosmetics → compressed read-only DMG.

> **Note:** DMGs from this script are not code-signed or notarized. Recipients may need **Right-click → Open** on first launch.

To bump the version, update `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `Chrono.xcodeproj` and `VERSION` / `BUILD_NUMBER` in `scripts/build-dmg.sh` together.

---

## Versioning

Chrono follows [Semantic Versioning](https://semver.org/):

| Component | Meaning |
|-----------|---------|
| **MAJOR** | Breaking changes or major redesign |
| **MINOR** | New features, backward-compatible |
| **PATCH** | Bug fixes and polish |

The **build number** (`CURRENT_PROJECT_VERSION` in Xcode, `BUILD_NUMBER` in `build-dmg.sh`) increments on every shipped build — App Store Connect rejects any upload whose build number isn't higher than the last one.

---

## Changelog

### 2.0.0 — 2026-10-16

**Projects & redesign**

- Multiple projects, each with its own cumulative time; one active project, one running timer
- New UI per the 2.0 Figma design: glass panel, project list with total, hover ▶︎ / ⋯, inline new/rename, inline delete & reset confirmations
- Info is now a separate screen (shortcuts, Smart Auto-Pause, launch at login, version)
- Auto-pause per project with sleep detection; idle time is excluded from the total
- Persistence: projects saved locally as JSON with periodic checkpoints; a crashed session is credited up to the last checkpoint
- Launch at login (SMAppService), off by default
- Removed the global ⌘Q hotkey that hijacked Quit in every app; only ⌘⇧S / ⌘⇧R are global
- Sandbox-safe idle detection via public `CGEventSource` APIs
- App Store readiness: privacy manifest, export-compliance key, archive script, review checklist

### 1.0.1 — 2026-05-31

**Fix — popover expansion animation**

- Fixed the info pane expanding upward or jumping during open/close
- Window top edge is now pinned; only the bottom grows and shrinks
- Replaced competing AppKit + SwiftUI frame animations with a single pre-sized AppKit update and a SwiftUI mask reveal
- Pre-measures info pane height via a hidden layout twin so the final size is known before the first tap

### 1.0.0 — Initial release

- Menu bar timer with liquid glass floating panel
- Start / Stop / Reset controls and keyboard shortcuts
- Dynamic status bar pill with tabular digits
- macOS 26–aligned prominent floating element styling

---

## Project layout

| Path | Role |
|------|------|
| `Chrono/ChronoApp.swift` | App entry point, accessory activation policy, terminate flush |
| `Chrono/MenuBarManager.swift` | AppKit bridge — `NSStatusItem`, borderless `NSPanel` subclass, top-pinned sizing |
| `Chrono/TimerPopoverView.swift` | Main panel UI: header, hero clock, controls, project list, glass background |
| `Chrono/ProjectRowView.swift` | Project row (active / hover / inline edit / confirmation card) |
| `Chrono/InfoView.swift` | Info screen: shortcuts, auto-pause, launch at login, version |
| `Chrono/TimerStatusBarView.swift` | Menu bar pill |
| `Chrono/Project.swift` | `Project` model (Codable) |
| `Chrono/ProjectStore.swift` | Projects, active project, timer state, JSON persistence |
| `Chrono/TimeFormat.swift` | `clock` / `duration` formatting |
| `Chrono/Theme.swift` | Design tokens from Figma |
| `Chrono/ActivityMonitor.swift` | Idle and sleep detection → auto-pause |
| `Chrono/KeyboardShortcutManager.swift` | Global hotkeys (⌘⇧S, ⌘⇧R) |
| `Chrono/LaunchAtLogin.swift` | SMAppService wrapper |
| `Chrono/PrivacyInfo.xcprivacy` | Privacy manifest (no tracking, no data collected, required-reason APIs) |
| `scripts/archive-appstore.sh` | App Store archive + export |
| `scripts/ExportOptions-AppStore.plist` | Export options (`app-store-connect`) |
| `scripts/build-dmg.sh` | Direct-distribution DMG pipeline |
| `scripts/build-icns.sh` | Icon compilation from `Chrono/assets/icons/` |
| `docs/` | App Store checklist, metadata, privacy policy, 2.0 plan |
| `Chrono.xcodeproj/` | Xcode project |

`TimerViewModel.swift` was removed in 2.0 (replaced by `ProjectStore`).

---

## Architecture (summary)

**MenuBarManager** owns the `NSStatusItem` and a borderless `NSPanel` subclass (`canBecomeKey = true` so text fields work). SwiftUI reports its size through `onSizeChange`; AppKit applies one `setFrame(animate: false)` per state change with the top edge fixed.

**TimerPopoverView** swaps between the main content and **InfoView** with opacity crossfades only — no SwiftUI height animations, so AppKit and SwiftUI never run competing animations.

**ProjectStore** is the single source of truth (projects, active ID, running state, `tick`) and persists to `Application Support/Chrono/projects.json`.

**TimerStatusBarView** renders `TimeFormat.clock` with `.monospacedDigit()` so the pill width stays stable as digits change.

See `AGENTS.md` for constraints agents and contributors should follow when changing this codebase.
