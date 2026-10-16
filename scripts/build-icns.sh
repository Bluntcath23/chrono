#!/usr/bin/env bash
# =============================================================================
# build-icns.sh  —  Generates Chrono.icns from the exported PNG assets
#                   and copies slices into Assets.xcassets/AppIcon.appiconset
#
# Source PNGs required (in Chrono/assets/icons/):
#   Untitled-macOS-Default-1024x1024@1x.png   → 1024×1024  (master)
#   Untitled-macOS-Default-512x512@1x.png     → 512×512
#   Untitled-macOS-Default-256x256@1x.png     → 256×256
#   Untitled-macOS-Default-128x128@1x.png     → 128×128
#   Untitled-macOS-Default-32x32@1x.png       → 32×32
#   Untitled-macOS-Default-16x16@1x.png       → 16×16
#   (The @2x counterparts are used for Retina slots.)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
ICONS_SRC="$ROOT/Chrono/assets/icons"
ICONSET="$ROOT/build/Chrono.iconset"
APPICONSET="$ROOT/Chrono/Assets.xcassets/AppIcon.appiconset"
ICNS_OUT="$ROOT/build/Chrono.icns"

echo "▶ Creating iconset directory…"
mkdir -p "$ICONSET"

# Helper: copy a source file to the iconset with the expected name.
# Usage: copy_slot <src-file> <iconset-dest-name>
copy_slot() {
  local src="$1"
  local dest_name="$2"
  if [[ ! -f "$src" ]]; then
    echo "  ⚠️  Missing: $src — skipping slot $dest_name"
    return
  fi
  cp "$src" "$ICONSET/$dest_name"
  echo "  ✔ $dest_name"
}

# iconutil expects EXACTLY these filenames inside a .iconset folder:
copy_slot "$ICONS_SRC/Untitled-macOS-Default-16x16@1x.png"     "icon_16x16.png"
copy_slot "$ICONS_SRC/Untitled-macOS-Default-16x16@2x.png"     "icon_16x16@2x.png"
copy_slot "$ICONS_SRC/Untitled-macOS-Default-32x32@1x.png"     "icon_32x32.png"
copy_slot "$ICONS_SRC/Untitled-macOS-Default-32x32@2x.png"     "icon_32x32@2x.png"
copy_slot "$ICONS_SRC/Untitled-macOS-Default-128x128@1x.png"   "icon_128x128.png"
copy_slot "$ICONS_SRC/Untitled-macOS-Default-128x128@2x.png"   "icon_128x128@2x.png"
copy_slot "$ICONS_SRC/Untitled-macOS-Default-256x256@1x.png"   "icon_256x256.png"
copy_slot "$ICONS_SRC/Untitled-macOS-Default-256x256@2x.png"   "icon_256x256@2x.png"
copy_slot "$ICONS_SRC/Untitled-macOS-Default-512x512@1x.png"   "icon_512x512.png"
copy_slot "$ICONS_SRC/Untitled-macOS-Default-1024x1024@1x.png" "icon_512x512@2x.png"

echo ""
echo "▶ Running iconutil to compile .icns…"
iconutil --convert icns --output "$ICNS_OUT" "$ICONSET"
echo "  ✔ Written: $ICNS_OUT"

echo ""
echo "▶ Syncing slices into Assets.xcassets/AppIcon.appiconset…"
mkdir -p "$APPICONSET"
for f in "$ICONSET"/*.png; do
  cp "$f" "$APPICONSET/$(basename "$f")"
  echo "  ✔ xcassets ← $(basename "$f")"
done

echo ""
echo "✅ ICNS build complete: $ICNS_OUT"
