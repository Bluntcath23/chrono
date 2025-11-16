## Chrono

Lightweight macOS menu bar timer.

### Prerequisites
- Xcode 15.4 (or compatible) on macOS 14+
- Swift toolchain bundled with Xcode (Swift 5.10.x)

### Open and Run
```bash
# From repo root
open Chrono.xcodeproj
```
In Xcode:
- Select the `Chrono` scheme and target `My Mac`.
- Press Run (▶). The app launches to the menu bar.

### Build from Terminal
```bash
cd /Users/k.bekher/Projects/Ivan/chrono
xcodebuild -scheme Chrono -configuration Debug -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/Chrono.app
```

### If you see “future Xcode project file format”
This happens when the project was saved with a newer Xcode. This repo is configured to open with Xcode 15.4:
- `Chrono.xcodeproj/project.pbxproj` has been set to Xcode 15 compatibility (objectVersion 60).
- If you still get the dialog, clean derived data and reopen:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
open Chrono.xcodeproj
```

### Switching Xcode versions (if you keep multiple)
```bash
# Point CLI tools to a specific Xcode
sudo xcode-select -s /Applications/Xcode.app        # or /Applications/Xcode-15.4.app

# Accept license to avoid first-run errors
sudo xcodebuild -license accept

# Verify
xcodebuild -version
swift --version
```

### First‑run macOS permissions
You may be prompted to grant:
- Accessibility (for global keyboard shortcuts)
- Input Monitoring (if used by features)

### Troubleshooting
- Clean build data: `Shift + Cmd + K` in Xcode, or remove `~/Library/Developer/Xcode/DerivedData`.
- Ensure Command Line Tools is set in Xcode → Settings → Locations → Command Line Tools: “Xcode 15.4”.
- If the project was opened in a newer Xcode and upgraded, revert the `.xcodeproj` changes or re‑clone this repo.

### Project layout
- `Chrono/` Swift sources and assets
- `Chrono.xcodeproj/` Xcode project


