# Chrono 2.0 — App Store metadata (ready to paste)

Field limits are from [App Store Connect Help → App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) and [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information). Character counts below were measured.

## App name (≤30 chars, must be unique on the store)

"Chrono" on its own is almost certainly taken. Pick one and try it when you create the app record (phase D). The name is locked in once you submit, but you can still change it in a later version.

| # | Name | Chars |
|---|------|-------|
| 1 | **Chrono – Menu Bar Timer** (recommended) | 23 |
| 2 | Chrono: Project Time Tracker | 28 |
| 3 | Chrono Time Tracker | 19 |

## Subtitle (≤30 chars)

```
Project time in your menu bar
```
(29 chars). Alternative: `Track time per project` (22).

## Promotional text (≤170 chars, editable any time without review)

```
Track time across all your projects from the menu bar. One click to start, one shortcut to stop, and Chrono pauses on its own when you step away.
```

## Description (≤4000 chars, plain text)

```
Chrono is a small, fast time tracker that lives in your menu bar. Give each project its own timer, switch between them in a click, and always know where your hours went.

PROJECTS
• Create as many projects as you need. Each one keeps its own running total.
• Click a project to make it active, or press ▶ to switch and start in one move.
• Rename, reset, or delete projects from the ⋯ menu or with a right-click. Destructive actions always ask first.
• See the total across all projects at a glance.

ALWAYS IN REACH
• The current time shows in a compact pill in your menu bar.
• Start or stop from any app with ⌘⇧S. Reset the active project with ⌘⇧R.
• While the panel is open: ⌘⇧1–9 switches to and starts a project, ⌘N adds a new one.

SMART AUTO-PAUSE
• Chrono pauses the timer when you've been away from your Mac or when it goes to sleep.
• The time you were away is not counted.
• A quiet notification tells you what happened.

DESIGNED FOR macOS
• A floating glass panel that matches modern macOS.
• No Dock icon and no windows to manage. Chrono stays out of your way.
• Optional launch at login. It's off until you turn it on.

PRIVATE BY DESIGN
• No account, no sign-up, no internet connection.
• No analytics or tracking. Your projects and times are stored only on your Mac.

Chrono is free, with no ads and no in-app purchases.
```

## Keywords (≤100 bytes, comma-separated, no spaces after commas, name not repeated)

```
time tracker,timer,stopwatch,projects,hours,work log,focus,billable,freelance,menubar,timesheet
```

## Category

| Field | Value |
|-------|-------|
| Primary | Productivity |
| Secondary (optional) | Utilities |

## Other fields

| Field | Value |
|-------|-------|
| Copyright | `© 2026 Ivan Inozemtsev` |
| Support URL (required) | `https://github.com/Bluntcath23/chrono/issues` *(must reach real contact info: add design@inozemtsev.co to the repo README, or use a page on inozemtsev.co)* |
| Marketing URL (optional) | `https://github.com/Bluntcath23/chrono` |
| Privacy Policy URL (required) | `https://bluntcath23.github.io/chrono/PRIVACY` *(enable GitHub Pages first; see the hosting note at the end of `docs/PRIVACY.md`)* |
| Price | Free (Pricing and Availability → USD 0) |
| Age rating | Expected **4+** (answer "None/No" to everything) |
| App Privacy | Data Not Collected |

## App Review notes (App Review Information → Notes)

```
Chrono is a menu-bar-only app (LSUIElement). It has no Dock icon and no main window.

HOW TO USE
1. After launch, look for the time pill (e.g. "00:00.0") at the right side of the menu bar.
2. Click the pill to open the Chrono panel. Click it again, or click anywhere else, to close it.
3. Press Start to time the active project ("My Project" is created on first launch). Press Stop to pause.
4. Click "New Project" (or ⌘N while the panel is open) to add a project. Hover a row and click ▶ to switch and start. Use ⋯ or right-click for Rename / Reset Time / Delete.
5. Click the (i) icon for the Info screen: shortcuts, auto-pause explanation, and the Launch at login toggle (off by default).
6. To quit: right-click the menu bar pill and choose Quit (the status item menu), or press ⌘Q while the panel is open.

GLOBAL SHORTCUTS (registered with Carbon RegisterEventHotKey, no Accessibility permission needed)
• ⌘⇧S – start/stop the active project's timer
• ⌘⇧R – reset the active project's timer
All other shortcuts work only while the panel is open.

AUTO-PAUSE
Chrono reads system idle time (CGEventSourceSecondsSinceLastEventType) and listens for sleep notifications. If the Mac is idle for 5 minutes or goes to sleep, the timer pauses, the idle time is dropped, and a local notification is shown. No input events are recorded.

No login, account, network access, or in-app purchases. All data is stored locally in the app's sandbox container.
```

> Before you submit, check step 6 (how to quit) against the final build and edit it to match what the app actually does.

## What's New (2.0)

You can't fill this in for the **first** version of an app in App Store Connect ([source](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)). Save this text for the release notes or the GitHub release, and reuse its style for 2.0.1:

```
Chrono 2.0 is a full redesign.
• Projects: track time separately for each project, with a running total.
• New glass panel, rebuilt for modern macOS.
• Smart auto-pause per project: pauses when you're away or the Mac sleeps, without counting the idle time.
• Your projects and times are saved automatically.
• Optional launch at login.
• New Info screen with all keyboard shortcuts.
• ⌘Q is no longer captured globally. Chrono now registers only ⌘⇧S and ⌘⇧R system-wide.
```

## Screenshot shot-list

Accepted Mac sizes (16:10): **1280×800, 1440×900, 2560×1600, 2880×1800**. Use PNG or JPEG with no alpha channel. You need 1 to 10 ([spec](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)). Recommended: **2880×1800**. Use a clean desktop with the panel open under the menu bar pill, and add each caption above the panel as overlay text.

| # | Figma state | What to show | Caption |
|---|-------------|--------------|---------|
| 1 | Running with project list | Panel open, active project running (live bars), 4–5 realistic projects, total in the header, pill visible in the menu bar | **Every project, its own timer.** |
| 2 | Paused, hover to switch | Timer paused, cursor hovering an inactive row so ▶︎ and ⋯ show, tooltip "Switch & start ⌘⇧2" | **Switch projects in one click.** |
| 3 | New project inline input | Inline field focused with a name typed, blue border, footer "Return to save · Esc to cancel" | **Add a project without leaving your flow.** |
| 4 | Delete confirmation | Red inline card `Delete "Branding"?` with Cancel / Delete | **Nothing disappears by accident.** |
| 5 | Info / shortcuts | Info screen: shortcut box, Smart Auto-Pause, Launch at login toggle | **Shortcuts and auto-pause built in.** |

Tips: use the same wallpaper in every shot, use believable project names and times (for example "Branding 2h 04m"), and don't show personal data or other apps' notifications.
