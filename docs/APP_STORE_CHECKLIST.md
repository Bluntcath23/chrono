# Chrono 2.0 — Mac App Store checklist

These steps take Chrono from "no developer account" to **Ready for Distribution**. App Store Connect used to call this status "Ready for Sale". The phases are in order, and each one depends on the one before it.

Pasteable text is in [`APP_STORE_METADATA.md`](APP_STORE_METADATA.md). The privacy policy is in [`PRIVACY.md`](PRIVACY.md).

## What to expect

| Phase | What | Your time | Waiting on Apple |
|-------|------|-----------|------------------|
| A | Developer Program enrollment | 30 min | Usually 1–2 days for individuals (Apple doesn't publish a number) |
| B | Agreements | 5 min | None |
| C | Xcode signing | 20 min | None |
| D | App record | 15 min | None |
| E | Metadata and screenshots | 2–4 h | None |
| F | Privacy, age rating, compliance | 20 min | None |
| G | Archive and upload | 30 min | 15 min to a few hours of processing |
| H | TestFlight (optional) | 1–3 days of real use | Internal testing needs no review |
| I | Submit for review | 15 min | Usually 1–3 days. Rejections are common for first apps, so plan for one round |
| J | Pre-flight against rejection reasons | 30 min | None |
| K | Release | 5 min | Up to 24 h to appear in every storefront |

**Realistic total:** about 1 week from enrollment to live, with roughly 1 day of hands-on work.

Legend: `- [x]` means it's already done in the repo (2.0 branch) and was verified in a Release build on 2026-10-16.

---

## A. Apple Developer Program enrollment (about 30 min, then 1–2 days)

Source: [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/) · [Enrollment support](https://developer.apple.com/support/enrollment/)

- [ ] **Pick an entity type.**

  | | Individual (recommended for Chrono) | Organization |
  |---|---|---|
  | Seller name on the store | Your legal name ("Ivan Inozemtsev") | Company legal name |
  | D-U-N-S Number | Not needed | Required (free, can take days to weeks) |
  | Needs | Legal name, address (no P.O. box), phone | Legal entity, binding authority, domain email, public website |
  | Cost | US$99/year (local currency) | US$99/year |

- [ ] Apple ID has **two-factor authentication** turned on (System Settings → your name → Sign-In & Security).
- [ ] Use your **legal name** exactly as it appears on your ID. A nickname or alias delays approval.
- [ ] Enroll in the **Apple Developer app** (Mac, iPhone, or iPad), which is the fastest route, or at developer.apple.com/programs/enroll. Pay with a card in **your own name**.
- [ ] Wait for the "Welcome to the Apple Developer Program" email. If you have no confirmation 24 h after paying, contact Developer Support with your Enrollment ID.
- [ ] Note your **Team ID**: developer.apple.com → Account → Membership details (10 characters, for example `AB12CD34EF`).
- [ ] Calendar reminder: membership renews yearly. If it lapses, the app is removed from sale.

## B. Agreements, tax, banking (about 5 min)

- [ ] Sign in to [App Store Connect](https://appstoreconnect.apple.com) → **Business** (formerly "Agreements, Tax, and Banking").
- [ ] Accept any pending agreement banners. The **Free Apps Agreement** is part of the Developer Program License Agreement, so it's active as soon as you enroll.
- [ ] **No banking or tax forms are needed for a free app.** The *Paid Apps* agreement, banking, and tax forms only matter if you add pricing or in-app purchases later.
- [ ] **EU trader status (Digital Services Act)**: you'll be asked when you first submit ([details](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)).
  - Free hobby app, no revenue or commercial activity: you're likely **not a trader**. EU users then see a note that consumer-protection rights don't apply.
  - If you declare yourself a trader, your **address, phone, and email are shown publicly** in EU storefronts.
  - Alternatively, leave the app out of EU storefronts. This is not legal advice, so decide for yourself.

## C. Xcode signing setup (about 20 min)

- [ ] Xcode → **Settings → Accounts** → **+** → Apple ID → sign in with the enrolled account.
- [ ] Open `Chrono.xcodeproj` → target **Chrono** → **Signing & Capabilities**:
  - [ ] **Automatically manage signing**: on. `CODE_SIGN_STYLE = Automatic` is already set in the project (verified).
  - [ ] **Team**: your team. This writes `DEVELOPMENT_TEAM` into the project (it's empty today, verified). `scripts/archive-appstore.sh` refuses to run until it's set.
  - [ ] **Bundle Identifier**: `com.inozemtsev.Chrono` (verified in project).
- [ ] Register the bundle ID. Automatic signing usually does this for you. If it doesn't, go to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) → Identifiers → **+** → App IDs → App → *Explicit* `com.inozemtsev.Chrono`. No extra capabilities are needed.
- [ ] Put the Team ID into `scripts/ExportOptions-AppStore.plist` (replace `YOUR_TEAM_ID`).
- [ ] Do a Debug build and run it once so Xcode creates the Development certificate. Xcode creates the **Apple Distribution** certificate automatically the first time you distribute.
- [ ] Commit the signing change. It's a one-line `DEVELOPMENT_TEAM` diff in `project.pbxproj`.

## D. App record in App Store Connect (about 15 min)

- [ ] App Store Connect → **Apps → + → New App**:

  | Field | Value |
  |-------|-------|
  | Platform | **macOS** |
  | Name | `Chrono – Menu Bar Timer` (try the alternatives in METADATA if it's taken; 2–30 chars, unique on the store) |
  | Primary language | English (U.S.) |
  | Bundle ID | `com.inozemtsev.Chrono` (appears in the dropdown once phase C is done) |
  | SKU | `chrono-macos` (internal and permanent; letters, numbers, `-`, `.`, `_`) |
  | User access | Full access |

- [ ] App Information → **Category**: Primary **Productivity**, secondary *Utilities* (optional).
- [ ] App Information → **Content Rights**: "No, it does not contain, show, or access third-party content."
- [ ] Pricing and Availability → **Free** (USD 0.00). Pick countries, including the EU decision from phase B.

## E. Metadata and assets (about 2–4 h, mostly screenshots)

Limits are from [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information), [Platform version info](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information), and [Screenshot specs](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/).

| Field | Limit | Status |
|-------|-------|--------|
| Name | 2–30 chars | Draft in METADATA |
| Subtitle | ≤30 chars | Draft (29) |
| Promotional text | ≤170 chars, editable without review | Draft (145) |
| Description | ≤4000 chars, plain text | Draft (about 1340) |
| Keywords | ≤100 bytes, comma-separated, no app name | Draft (95) |
| Support URL | Required, must reach real contact info | Placeholder |
| Privacy policy URL | Required for macOS | Placeholder (host `PRIVACY.md`) |
| What's New | **Not available on the first version** | Saved for 2.0.1 |

- [ ] Paste name, subtitle, promotional text, description, and keywords from `APP_STORE_METADATA.md`.
- [ ] **Host the privacy policy.** The repo is public on GitHub, so GitHub Pages from `/docs` on `main` works (see the end of `PRIVACY.md`). The contact (design@inozemtsev.co) is already filled in.
- [ ] **Support URL**: a page with a way to contact you, such as the GitHub repo or issues with your email in the README, or the Pages site.
- [ ] Copyright: `© 2026 Ivan Inozemtsev`.
- [ ] **Screenshots**: 1–10, all one 16:10 size: **1280×800, 1440×900, 2560×1600, or 2880×1800**. PNG or JPEG, **no alpha channel**. Follow the 5-shot list in METADATA.
  - Capture on a Retina display at default scaling, then crop or resize to 2880×1800. To flatten alpha, run `sips -s format jpeg in.png --out out.jpg`.
  - Show the real app, with no device frames that mislead (guideline 2.3).
- [x] **App icon** comes from the asset catalog: `Chrono/Assets.xcassets/AppIcon.appiconset` has every macOS slot, including the 1024 px `icon_512x512@2x.png`. There's no separate upload.
- [ ] Optional: App Preview video. Skip it for 1.0 of the listing.

## F. Privacy, age rating, export compliance (about 20 min)

- [ ] **App Privacy** → Get Started → "Do you or your third-party partners collect data from this app?" → **No** → the product page shows **Data Not Collected**. Enter the privacy policy URL here too.
- [ ] **Age rating** questionnaire: answer **None/No** to every item (no user-generated content, social feeds, web access, gambling, and so on). Expected result **4+**. Apple's 2025–26 rating system uses 4+/9+/13+/16+/18+, and new questions keep being added, so answer whatever is shown.
- [ ] **Export compliance**: Chrono uses no encryption beyond what the OS provides.
  - [x] `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` is set in the target build settings, so App Store Connect stops asking on every build.
- [x] **App Sandbox** enabled: `ENABLE_APP_SANDBOX = YES` (Debug and Release).
- [x] `Chrono/PrivacyInfo.xcprivacy`: tracking false, no collected data types, required-reason APIs UserDefaults `CA92.1`, SystemBootTime `35F9.1`, FileTimestamp `C617.1`. It's in Copy Bundle Resources and inside the built `.app`.
- [x] Info.plist keys (verified with `plutil -p` on the built app):
  - [x] `LSUIElement = YES` (`INFOPLIST_KEY_LSUIElement`), so no Dock icon even before `setActivationPolicy(.accessory)` runs
  - [x] `LSApplicationCategoryType = public.app-category.productivity`. Upload validation warns if it's missing.
  - [x] `NSHumanReadableCopyright = © 2026 Ivan Inozemtsev`
- [x] Entitlements: only `com.apple.security.app-sandbox`. The unused `ENABLE_USER_SELECTED_FILES` and `REGISTER_APP_GROUPS` were removed. Hardened Runtime is on.

## G. Build and upload (about 30 min, plus processing)

- [ ] Version: `MARKETING_VERSION = 2.0.0`, `CURRENT_PROJECT_VERSION = 3` in Xcode, and `VERSION`/`BUILD_NUMBER` in `scripts/build-dmg.sh`. Bump all of them together.
  - [x] `scripts/build-dmg.sh` updated to 2.0.0 / 3.
  - [x] Xcode project: 2.0.0 / 3.
- [ ] Build with the current **Xcode 26** release. Apple raises the minimum SDK for uploads periodically ([upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)).
- [ ] Clean Release build runs with no warnings that matter. Smoke-test the archived app (phase J).
- [ ] **Option 1, Xcode UI:** scheme Chrono, destination *Any Mac* → **Product → Archive** → Organizer opens → **Distribute App → App Store Connect → Upload** → keep the defaults (automatic signing, upload symbols) → Upload.
- [ ] **Option 2, script:** `bash scripts/archive-appstore.sh`
  - Creates `build/Chrono.xcarchive` and a signed `.pkg` in `dist/appstore/`.
  - Upload the `.pkg` with [Transporter](https://apps.apple.com/app/transporter/id1450874784) or Organizer, or set `destination` to `upload` in `scripts/ExportOptions-AppStore.plist` to upload directly.
- [ ] Wait for the "has completed processing" email (15 min to a few hours). The build then appears under **TestFlight** and can be selected on the version page.
- [ ] If the upload is rejected for "build number already used", bump `CURRENT_PROJECT_VERSION` and archive again. **Every upload needs a new, higher build number.**

## H. TestFlight for Mac (optional, recommended, 1–3 days of use)

- [ ] App Store Connect → TestFlight → **Internal Testing** → create a group and add yourself (up to 100 App Store Connect users, no beta review needed).
- [ ] Install **TestFlight** from the Mac App Store, accept the invite, and install Chrono.
- [ ] Run it for a real working day:
  - [ ] Fresh install seeds "My Project". Projects survive quit and relaunch.
  - [ ] ⌘⇧S and ⌘⇧R work from other apps. **⌘Q in other apps quits those apps, not Chrono.**
  - [ ] Idle for more than 5 min, or close the lid: the timer pauses, a notification appears, and idle time isn't counted.
  - [ ] Launch at login is off by default. Toggle it on, log out and back in, and confirm it works. Then turn it off.
  - [ ] The panel opens under the pill on every display and in light and dark mode. Text fields accept typing.
- [ ] External testing (outside your team) needs a short beta review. Skip it for this release.
- [ ] TestFlight builds expire after 90 days.

## I. Submit for review (about 15 min, then usually 1–3 days)

- [ ] On the macOS version page (2.0.0), under **Build**, select the processed build.
- [ ] **App Review Information**:
  - [ ] Sign-in required: **No**
  - [ ] Contact: name, phone, email
  - [ ] **Notes**: paste "App Review notes" from METADATA. It explains that the app lives only in the menu bar, where to click, the 2 global shortcuts, how to quit, and that no login is needed.
- [ ] Version release: choose **Manually release this version** for the first launch, so you control the day.
- [ ] **Add for Review → Submit**. Status goes *Waiting for Review → In Review → Pending Developer Release* (or *Ready for Distribution* with automatic release).
- [ ] If rejected: read the message in App Review (Resolution Center), fix the problem or reply with an explanation, and resubmit. Metadata-only fixes don't need a new build.

## J. Common rejection reasons for menu bar apps, and Chrono's status

| Guideline | Risk | How Chrono addresses it | Status |
|-----------|------|------------------------|-------|
| [2.4.5(i)](https://developer.apple.com/app-store/review/guidelines/#2.4.5) Sandboxed | Rejected outright if not sandboxed | `ENABLE_APP_SANDBOX = YES`. Data lives in the container (`Application Support/Chrono/projects.json`) | ✅ done |
| 2.4.5(iii) No auto-launch without consent | Login item enabled on first run | SMAppService launch at login is **off by default** and turned on only through the Info toggle | ✅ done (verify on TestFlight) |
| 2.4.5(iii) No Dock icons or desktop shortcuts | | `LSUIElement` / accessory policy, no Dock icon | ✅ done |
| 2.4.5(v) No root escalation, (vii) no custom updater | | None used. Updates come through the App Store only | ✅ done |
| [2.5.9](https://developer.apple.com/app-store/review/guidelines/#2.5.9) Altering native UI behaviors | v1 registered **global ⌘Q**, hijacking Quit in every app | 2.0 registers only ⌘⇧S and ⌘⇧R (Carbon `RegisterEventHotKey`). ⌘Q is removed | ✅ done |
| 2.5.1 Public APIs only | Private API use, or IOKit registry poking | Idle time via public `CGEventSource.secondsSinceLastEventType`, sleep via `NSWorkspace` notifications. *v1 read `HIDIdleTime` from IOKit; 2.0 no longer does* | ✅ done |
| Quit option (reviewers expect one; 4.0 / 2.1) | "Unable to quit the app" | "Quit Chrono" in the status item menu (right-click) and in the Info screen footer, plus ⌘Q while the panel is open | ✅ done |
| [2.1](https://developer.apple.com/app-store/review/guidelines/#2.1) Crashes or incomplete | Crash on first launch, empty state, placeholder text | Fresh install seeds "My Project". Corrupt or missing JSON falls back safely. No placeholder URLs | ☐ test a fresh install: `rm -rf ~/Library/Containers/com.inozemtsev.Chrono` |
| 4.0 / 4.2 Design, minimum functionality | "App is too simple" or doesn't look like a Mac app | Projects, totals, auto-pause, and shortcuts are real functionality. Native menus, light/dark mode | ☐ |
| [5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/#5.1.1) Privacy policy | Missing URL, **or no link inside the app** | URL in App Store Connect, plus `PRIVACY.md` | ✅ "Privacy Policy" link in the Info screen footer → `https://bluntcath23.github.io/chrono/PRIVACY` (`InfoView.privacyPolicyURL`). **Publish the page before submitting** |
| 5.1.2 / App Privacy accuracy | Label says no data but SDKs collect it | No SDKs, no network. "Data Not Collected" is accurate | ✅ done |
| Privacy manifest | ITMS-91053 "Missing API declaration" email after upload | `PrivacyInfo.xcprivacy` with the required-reason APIs | ✅ bundled |
| 2.3 Accurate metadata | Screenshots or description promise features the app doesn't have | Description lists only shipped features (no color, no daily reset, no export) | ☐ |
| Notifications | Permission prompt at launch with no context | Ask only when auto-pause first needs it, or on first Start | ✅ done |

## K. After approval

- [ ] **Release**:
  - Manual: click **Release This Version**.
  - Automatic: goes live as soon as it's approved.
  - Scheduled: "after date". It can take up to 24 h to appear in every storefront.
- [ ] Search the store for the app name, install it from the store on a clean account, and check it.
- [ ] Update `README.md` with the App Store link.
- [ ] **Ratings and reviews**: App Store Connect → Ratings and Reviews. You can reply publicly to each review once, and edit your reply. Be short and polite, and point to the fix version.
- [ ] Tag the release in git: `git tag v2.0.0 && git push --tags`.
- [ ] **Shipping 2.0.1** (bug fix):
  1. Bump `MARKETING_VERSION` to 2.0.1 **and** `CURRENT_PROJECT_VERSION` to 4 (or higher), plus `scripts/build-dmg.sh`, plus the README changelog.
  2. Archive and upload (phase G).
  3. App Store Connect → **+ Version or Platform** → 2.0.1, then fill in **What's New** (it's required from the second version on).
  4. Optional: **Phased Release for Automatic Updates** spreads the release over 7 days for users with auto-update on. It's available for updates only, not the first version, and you can pause it or release to everyone.
  5. Submit. Updates usually review faster.
- [ ] Promotional text can change any time without review. Use it for announcements.
