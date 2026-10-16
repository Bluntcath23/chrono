#!/usr/bin/env bash
# =============================================================================
# build-dmg.sh  —  Full release pipeline for Chrono.app → Chrono.dmg
#
# Prerequisites (all ship with macOS / Xcode):
#   xcodebuild, iconutil, hdiutil, sips, osascript
#
# Usage:
#   cd /path/to/chrono-app
#   bash scripts/build-dmg.sh
#
# Output:
#   dist/Chrono-2.0.0.dmg  (Chrono 2.0.0, build 3 — direct distribution, not App Store)
# =============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
APP_NAME="Chrono"
VERSION="2.0.0"
BUILD_NUMBER="3"
DMG_NAME="${APP_NAME}-${VERSION}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."

SCHEME="$APP_NAME"
XCODEPROJ="$ROOT/${APP_NAME}.xcodeproj"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_TEMP="$BUILD_DIR/${DMG_NAME}-rw.dmg"
DMG_FINAL="$DIST_DIR/${DMG_NAME}.dmg"

BG_IMAGE="$ROOT/Chrono/assets/dmg-bg.png"
ICNS_FILE="$BUILD_DIR/${APP_NAME}.icns"

# DMG window geometry
WIN_W=600
WIN_H=400
APP_X=150
APP_Y=200
LINK_X=450
LINK_Y=200

# ── Helpers ────────────────────────────────────────────────────────────────────
step() { echo ""; echo "══════════════════════════════════════════"; echo "  $*"; echo "══════════════════════════════════════════"; }
ok()   { echo "  ✔ $*"; }
fail() { echo "  ✘ ERROR: $*" >&2; exit 1; }

# ── 0. Preflight ───────────────────────────────────────────────────────────────
step "0/6  Preflight checks"
[[ -d "$XCODEPROJ" ]]  || fail "Xcode project not found: $XCODEPROJ"
[[ -f "$BG_IMAGE" ]]   || fail "DMG background not found: $BG_IMAGE"
mkdir -p "$BUILD_DIR" "$DIST_DIR"
ok "Directories ready"

# ── 1. Build .icns ─────────────────────────────────────────────────────────────
step "1/6  Building .icns"
bash "$SCRIPT_DIR/build-icns.sh"
[[ -f "$ICNS_FILE" ]] || fail "ICNS not produced — check build-icns.sh output"
ok "Chrono.icns ready"

# ── 2. Build .app ──────────────────────────────────────────────────────────────
step "2/6  Building ${APP_NAME}.app (Release)"
xcodebuild \
  -project "$XCODEPROJ" \
  -scheme   "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO \
  | tee "$BUILD_DIR/xcodebuild.log" \
  | grep -E "^(error:|Build succeeded)" || true

BUILT_APP=$(find "$BUILD_DIR/DerivedData" -name "${APP_NAME}.app" -maxdepth 8 | head -1)
[[ -n "$BUILT_APP" ]] || fail ".app bundle not found in DerivedData. Check $BUILD_DIR/xcodebuild.log"
ok "Found: $BUILT_APP"

# Copy to canonical location
rm -rf "$APP_BUNDLE"
cp -R "$BUILT_APP" "$APP_BUNDLE"
ok "Copied → $APP_BUNDLE"

# Patch Info.plist version strings
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
if [[ -f "$INFO_PLIST" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION"   "$INFO_PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER"         "$INFO_PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER"       "$INFO_PLIST"
  ok "Info.plist → CFBundleShortVersionString=$VERSION, CFBundleVersion=$BUILD_NUMBER"
fi

# Inject .icns so Finder shows the polished icon
RESOURCES="$APP_BUNDLE/Contents/Resources"
mkdir -p "$RESOURCES"
cp "$ICNS_FILE" "$RESOURCES/${APP_NAME}.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile ${APP_NAME}" "$INFO_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${APP_NAME}" "$INFO_PLIST"
ok "Injected ${APP_NAME}.icns into app bundle"

# ── 3. Stage the DMG content ───────────────────────────────────────────────────
step "3/6  Staging DMG content"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"
mkdir -p "$STAGING_DIR/.background"
cp "$BG_IMAGE" "$STAGING_DIR/.background/background.png"

ok "Staging complete: $STAGING_DIR"

# ── 4. Create read-write DMG, apply cosmetics, freeze ─────────────────────────
step "4/6  Creating DMG"
rm -f "$DMG_TEMP" "$DMG_FINAL"

hdiutil create \
  -srcfolder "$STAGING_DIR" \
  -volname   "$APP_NAME" \
  -fs        HFS+ \
  -fsargs    "-c c=64,a=16,b=16" \
  -format    UDRW \
  -size      200m \
  "$DMG_TEMP"
ok "Writable DMG created: $DMG_TEMP"

# Mount — use -mountrandom so we get a clean, known path
MOUNT_OUTPUT=$(hdiutil attach "$DMG_TEMP" -readwrite -noverify -noautoopen -mountrandom /tmp)
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | awk 'END{print $NF}')
[[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]] || fail "Could not determine mount point from: $MOUNT_OUTPUT"
ok "Mounted at: $MOUNT_POINT"

# Let the volume settle before Finder talks to it
sleep 3

# Apply cosmetics via AppleScript using the POSIX path (robust — avoids disk-name lookup race)
osascript - "$MOUNT_POINT" "$APP_NAME" "$APP_X" "$APP_Y" "$LINK_X" "$LINK_Y" "$WIN_W" "$WIN_H" <<'APPLESCRIPT'
on run argv
  set mountPath   to item 1 of argv
  set appName     to item 2 of argv
  set appX        to (item 3 of argv) as integer
  set appY        to (item 4 of argv) as integer
  set linkX       to (item 5 of argv) as integer
  set linkY       to (item 6 of argv) as integer
  set winW        to (item 7 of argv) as integer
  set winH        to (item 8 of argv) as integer

  tell application "Finder"
    -- Open the volume by its POSIX path (never races on disk name)
    set thedisk to (POSIX file mountPath) as alias
    open thedisk

    set win to container window of thedisk

    try
      set current view of win to icon view
    end try
    -- toolbar/statusbar toggling can be refused by the sandbox; wrap individually
    try
      set toolbar visible of win to false
    end try
    try
      set statusbar visible of win to false
    end try
    try
      set sidebar width of win to 0
    end try

    -- Centre the 600×400 window on screen
    set offsetX to 400
    set offsetY to 100
    try
      set the bounds of win to {offsetX, offsetY, offsetX + winW, offsetY + winH}
    end try

    set opts to icon view options of win
    try
      set arrangement of opts to not arranged
    end try
    try
      set icon size of opts to 80
    end try
    try
      set background picture of opts to file ".background:background.png" of thedisk
    end try

    try
      set position of item (appName & ".app") of win to {appX, appY}
    end try
    try
      set position of item "Applications" of win to {linkX, linkY}
    end try

    -- Force-flush the metadata
    update thedisk
    delay 3
    try
      close win
    end try
  end tell
end run
APPLESCRIPT
ok "Finder cosmetics applied"

# Place the volume icon
cp "$ICNS_FILE" "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
ok "Volume icon set"

# Sync and detach
sync
sleep 1
hdiutil detach "$MOUNT_POINT" -quiet
ok "Unmounted"

# ── 5. Convert to read-only, compressed DMG ────────────────────────────────────
step "5/6  Compressing DMG"
hdiutil convert "$DMG_TEMP" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_FINAL"
ok "Final DMG: $DMG_FINAL"
rm -f "$DMG_TEMP"

# ── 6. Done ────────────────────────────────────────────────────────────────────
step "6/6  Complete"
DMG_SIZE=$(du -sh "$DMG_FINAL" | cut -f1)
echo ""
echo "  📦  ${DMG_NAME}.dmg  ($DMG_SIZE)"
echo "  📍  $DMG_FINAL"
echo ""
echo "  ⚠️  The DMG is NOT code-signed or notarized."
echo "     Recipients will need to right-click → Open on first launch."
echo ""
