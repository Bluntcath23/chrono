# Chrono Privacy Policy

**Effective date:** 2026-10-16
**App:** Chrono for macOS (bundle ID `com.inozemtsev.Chrono`)
**Developer:** Ivan Inozemtsev

## The short version

Chrono does not collect, transmit, sell, or share any data. Everything stays on your Mac.

## What Chrono stores

| Data | Where it lives | Why |
|------|----------------|-----|
| Project names and tracked time | A JSON file in Chrono's sandboxed Application Support folder on your Mac | So your projects and totals are there the next time you open Chrono |
| App preferences (for example, launch at login) | macOS user defaults for Chrono, on your Mac | So your settings are remembered |

This data never leaves your device. Chrono has no accounts, no servers, and no network access.

## What Chrono does not do

- No analytics, telemetry, crash reporting SDKs, or advertising
- No tracking across apps or websites
- No third-party services or SDKs
- No access to your files, contacts, location, camera, or microphone

## Notifications

Chrono can show a local notification when it pauses a timer automatically (for example, after you have been away from your Mac). macOS creates these notifications on your device. Nothing is sent to Apple or anyone else.

## Activity detection

To pause automatically when you step away, Chrono asks macOS how many seconds have passed since your last keyboard or mouse input, and whether the Mac is going to sleep. Chrono reads only that elapsed-time number. It never records what you type or click.

## Deleting your data

- To delete a project and its time, use **Delete Project…** in Chrono.
- To remove everything, quit Chrono and move it to the Trash. You can also delete `~/Library/Containers/com.inozemtsev.Chrono`.

## Children

Chrono collects no personal information from anyone, including children.

## Changes

If this policy changes, the new version will be posted at this URL with a new effective date.

## Contact

Questions about this policy or the app: Ivan Inozemtsev, [design@inozemtsev.co](mailto:design@inozemtsev.co)

---

<!-- Not part of the policy. Remove everything below this line before publishing it elsewhere. -->

## Hosting note (not part of the policy)

App Store Connect needs a **public URL** for the privacy policy, and guideline 5.1.1(i) asks for a link inside the app as well. Free ways to host it:

| Option | Steps | Resulting URL |
|--------|-------|---------------|
| **GitHub Pages** (recommended; the repo is `github.com/Bluntcath23/chrono`) | The repository must be **public** (Pages on private repos needs a paid plan). Go to Settings → Pages → Source: *Deploy from a branch*, choose branch `main` and folder `/docs`, then save. Merge this file to `main` | `https://bluntcath23.github.io/chrono/PRIVACY` (lowercase `privacy` does not work, because Pages paths are case-sensitive) |
| GitHub Gist | Create a **public** gist named `chrono-privacy.md` and paste in the policy | `https://gist.github.com/Bluntcath23/<id>` |
| Notion | Create a page, paste in the policy, then Share → Publish to web | `https://<workspace>.notion.site/...` |

Before you submit, open the URL in a private browser window to confirm that it loads without a login.
