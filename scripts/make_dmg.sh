#!/usr/bin/env bash
#
# Builds CDJ USB (release), code-signs with a Developer ID, packages a .dmg,
# and (if a notary profile is set) notarizes + staples it. macOS built-ins only.
#
# A distributable, warning-free .dmg requires the paid Apple Developer Program.
# Configure via env vars (see SIGNING.md):
#   CDJUSB_SIGN_IDENTITY  e.g. "Developer ID Application: Your Name (TEAMID)"
#   CDJUSB_NOTARY_PROFILE name of a notarytool keychain profile
# If unset, this still produces a working but unsigned DMG.
#
# Usage:  ./scripts/make_dmg.sh
# Output: dist/CDJ-USB-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="CDJ USB"
VOL_NAME="CDJ USB"
BUILT_APP="build/macos/Build/Products/Release/CDJ USB.app"
ENTITLEMENTS="macos/Runner/Release.entitlements"
DIST_DIR="dist"

# Pick up signing config from an untracked local file so you don't have to
# export env vars every run. scripts/signing.env (gitignored) may set
# CDJUSB_SIGN_IDENTITY and/or CDJUSB_NOTARY_PROFILE; real env vars still win.
if [ -f scripts/signing.env ]; then
  # shellcheck disable=SC1091
  . scripts/signing.env
fi

SIGN_ID="${CDJUSB_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${CDJUSB_NOTARY_PROFILE:-}"

# Fall back to the Developer ID Application identity in your keychain.
if [ -z "$SIGN_ID" ]; then
  SIGN_ID="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1 || true)"
  [ -n "$SIGN_ID" ] && echo "==> Auto-detected signing identity: $SIGN_ID"
fi

VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | cut -d'+' -f1)"
[ -z "$VERSION" ] && VERSION="0.0.0"
DMG_PATH="$DIST_DIR/CDJ-USB-${VERSION}.dmg"

echo "==> Building release app..."
flutter build macos --release

if [ ! -d "$BUILT_APP" ]; then
  echo "error: built app not found at $BUILT_APP" >&2
  exit 1
fi

echo "==> Staging disk image contents..."
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
STAGED_APP="$STAGE/${APP_NAME}.app"
cp -R "$BUILT_APP" "$STAGED_APP"
ln -s /Applications "$STAGE/Applications"

if [ -n "$SIGN_ID" ]; then
  echo "==> Code signing with: $SIGN_ID"
  # Sign nested frameworks/dylibs first (inside-out) — incl. SQLCipher — then the
  # app with the hardened runtime (required for notarization). Re-signing the
  # bundled frameworks with your Developer ID keeps library validation happy.
  find "$STAGED_APP/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) -print0 2>/dev/null \
    | while IFS= read -r -d '' lib; do
        codesign --force --timestamp --options runtime --sign "$SIGN_ID" "$lib"
      done
  codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$STAGED_APP"
  codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
else
  echo "==> No CDJUSB_SIGN_IDENTITY set -- producing an UNSIGNED app."
fi

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "==> Rendering DMG background..."
BG_TMP="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$BG_TMP"' EXIT
swift scripts/dmg_background.swift "$BG_TMP"
mkdir "$STAGE/.background"
tiffutil -cathidpicheck "$BG_TMP/bg1x.png" "$BG_TMP/bg2x.png" \
  -out "$STAGE/.background/background.tiff" >/dev/null 2>&1

echo "==> Creating $DMG_PATH ..."
RW_DMG="$BG_TMP/rw.dmg"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDRW \
  -size 300m \
  -ov \
  "$RW_DMG" >/dev/null

MOUNT_DIR="/Volumes/$VOL_NAME"
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
hdiutil attach "$RW_DMG" >/dev/null

echo "==> Laying out Finder window (icon positions, background)..."
# Hidden items (.background, .fseventsd, ...) must be positioned out of view
# first: Finder's no-overlap logic otherwise shoves the visible icons off
# their assigned spots.
osascript <<EOF
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    repeat with hiddenName in {".background", ".fseventsd", ".DS_Store", ".VolumeIcon.icns", ".Trashes"}
      try
        set position of item hiddenName of container window to {1000, 700}
      end try
    end repeat
    set position of item "${APP_NAME}.app" of container window to {165, 185}
    set position of item "Applications" of container window to {495, 185}
    close
    open
    set position of item "${APP_NAME}.app" of container window to {165, 185}
    set position of item "Applications" of container window to {495, 185}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

if [ -f "$STAGED_APP/Contents/Resources/AppIcon.icns" ] && command -v SetFile >/dev/null; then
  cp "$STAGED_APP/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
  SetFile -a C "$MOUNT_DIR"
fi

sync
hdiutil detach "$MOUNT_DIR" >/dev/null
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null

if [ -n "$SIGN_ID" ]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG_PATH"
fi

if [ -n "$SIGN_ID" ] && [ -n "$NOTARY_PROFILE" ]; then
  echo "==> Notarizing (this can take a few minutes)..."
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling ticket..."
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  echo ""
  echo "Done (signed + notarized): $DMG_PATH"
elif [ -n "$SIGN_ID" ]; then
  echo ""
  echo "Done (signed, NOT notarized): $DMG_PATH"
  echo "Set CDJUSB_NOTARY_PROFILE to notarize for warning-free distribution."
else
  echo ""
  echo "Done (unsigned): $DMG_PATH"
  echo "On first launch: right-click > Open (or xattr -dr com.apple.quarantine \"/Applications/${APP_NAME}.app\")."
fi
