#!/usr/bin/env bash
# =============================================================================
# archive-appstore.sh  —  Archive Chrono for the Mac App Store and export it
#
# Prerequisites:
#   - Apple Developer Program membership
#   - Xcode → Settings → Accounts signed in with that Apple ID
#   - DEVELOPMENT_TEAM set on the Chrono target (Signing & Capabilities → Team)
#   - teamID in scripts/ExportOptions-AppStore.plist replaced with your Team ID
#
# Usage:
#   cd /path/to/chrono-app
#   bash scripts/archive-appstore.sh
#
# Output:
#   build/Chrono.xcarchive        (also visible in Xcode → Window → Organizer)
#   dist/appstore/Chrono.pkg      (when ExportOptions destination = export)
#
# To upload straight to App Store Connect instead of exporting a .pkg,
# switch `destination` to `upload` in scripts/ExportOptions-AppStore.plist.
# =============================================================================

set -euo pipefail

APP_NAME="Chrono"
SCHEME="$APP_NAME"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
XCODEPROJ="$ROOT/${APP_NAME}.xcodeproj"
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/${APP_NAME}.xcarchive"
EXPORT_DIR="$ROOT/dist/appstore"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions-AppStore.plist"

step() { echo ""; echo "══════════════════════════════════════════"; echo "  $*"; echo "══════════════════════════════════════════"; }
ok()   { echo "  ✔ $*"; }
fail() { echo "  ✘ ERROR: $*" >&2; exit 1; }

# ── 0. Preflight ───────────────────────────────────────────────────────────────
step "0/3  Preflight checks"
command -v xcodebuild >/dev/null || fail "xcodebuild not found — install Xcode and run: xcode-select -s /Applications/Xcode.app"
[[ -d "$XCODEPROJ" ]]      || fail "Xcode project not found: $XCODEPROJ"
[[ -f "$EXPORT_OPTIONS" ]] || fail "Export options not found: $EXPORT_OPTIONS"

SETTINGS="$(xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null)" \
  || fail "xcodebuild -showBuildSettings failed — open the project in Xcode to check for errors"

setting() { echo "$SETTINGS" | awk -F' = ' -v key="$1" '$1 ~ "^[[:space:]]*"key"$" { print $2; exit }'; }

VERSION="$(setting MARKETING_VERSION)"
BUILD_NUMBER="$(setting CURRENT_PROJECT_VERSION)"
BUNDLE_ID="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
TEAM_ID="$(setting DEVELOPMENT_TEAM)"

[[ -n "$VERSION" ]]      || fail "MARKETING_VERSION is empty"
[[ -n "$BUILD_NUMBER" ]] || fail "CURRENT_PROJECT_VERSION is empty"
[[ -n "$TEAM_ID" ]] || fail "DEVELOPMENT_TEAM is empty.
     Open Chrono.xcodeproj → target Chrono → Signing & Capabilities → Team,
     pick your Apple Developer team, then re-run. See docs/APP_STORE_CHECKLIST.md (phase C)."

if grep -q "YOUR_TEAM_ID" "$EXPORT_OPTIONS"; then
  fail "Replace YOUR_TEAM_ID in $EXPORT_OPTIONS with your Team ID ($TEAM_ID)"
fi

ok "Bundle ID:  $BUNDLE_ID"
ok "Version:    $VERSION (build $BUILD_NUMBER)"
ok "Team:       $TEAM_ID"
echo "  ℹ Build number must be higher than every build already uploaded for this version."

mkdir -p "$BUILD_DIR" "$EXPORT_DIR"

# ── 1. Archive ─────────────────────────────────────────────────────────────────
step "1/3  Archiving ${APP_NAME} (Release)"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
  -project "$XCODEPROJ" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  | tee "$BUILD_DIR/archive.log" \
  | grep -E "^(error:|\*\* ARCHIVE)" || true

[[ -d "$ARCHIVE_PATH" ]] || fail "Archive not produced. Check $BUILD_DIR/archive.log"
ok "Archive: $ARCHIVE_PATH"

# ── 2. Export / upload ─────────────────────────────────────────────────────────
step "2/3  Exporting for App Store Connect"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  | tee "$BUILD_DIR/export.log" \
  | grep -E "^(error:|\*\* EXPORT)" || true

grep -q "EXPORT SUCCEEDED" "$BUILD_DIR/export.log" || fail "Export failed. Check $BUILD_DIR/export.log"
ok "Export output: $EXPORT_DIR"

# ── 3. Done ────────────────────────────────────────────────────────────────────
step "3/3  Complete"
echo ""
echo "  📦  ${APP_NAME} ${VERSION} (${BUILD_NUMBER})"
echo "  📍  $EXPORT_DIR"
echo ""
echo "  Next: upload the .pkg with Transporter (Mac App Store), or open the"
echo "  archive in Xcode → Organizer → Distribute App → App Store Connect → Upload."
echo "  (If ExportOptions destination = upload, the build is already on its way.)"
echo ""
