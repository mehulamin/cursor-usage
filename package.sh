#!/usr/bin/env bash
#
# package.sh — Zip an already-built Cursor Usage.app for your other Macs.
#
# Expects dist/Cursor Usage.app (from ./build.sh or ./install.sh).
# No Apple Developer Program required. The app is ad-hoc signed; on each target
# Mac you approve it once via Gatekeeper (see "Install on another Mac" below).
#
# Usage:
#   ./package.sh
#     → dist/Cursor-Usage-<version>-macOS-arm64.zip
#     → also copied to ~/data/bin/dist/
#
# Install on another Mac:
#   1. Copy the ZIP (AirDrop, USB, iCloud Drive, etc.) and unzip it.
#   2. Drag "Cursor Usage.app" into /Applications (or ~/Applications).
#   3. First launch only: Right-click the app → Open → Open in the dialog.
#      Or: try to open → System Settings → Privacy & Security → Open Anyway.
#   4. Later launches work normally.
#
# If macOS quarantined a downloaded copy:
#   xattr -cr "/Applications/Cursor Usage.app"
#   Then open again (you may still need Right-click → Open once).
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ui.sh
source "$ROOT/Scripts/ui.sh"

APP_NAME="Cursor Usage"
DIST="$ROOT/dist"
APP="$DIST/${APP_NAME}.app"
PLIST="$ROOT/Resources/Info.plist"
SHARE_DIST="${HOME}/data/bin/dist"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || echo "0.0.0")"
ZIP_NAME="Cursor-Usage-${VERSION}-macOS-arm64.zip"
ZIP_PATH="$DIST/$ZIP_NAME"
SHARE_ZIP="$SHARE_DIST/$ZIP_NAME"

banner "package"
if [[ ! -d "$APP" ]]; then
  fail "Expected app bundle at ${APP} (run ./build.sh or ./install.sh first)"
fi
step "Creating ZIP…"
rm -f "$ZIP_PATH"
(
  cd "$DIST"
  ditto -c -k --keepParent "${APP_NAME}.app" "$ZIP_NAME"
)
ok "Created ZIP  →  ${C_DIM}${ZIP_PATH}${C_RESET}"

# Keep only the current app + this ZIP in dist/.
step "Cleaning older builds in dist/…"
shopt -s nullglob
for item in "$DIST"/*; do
  [[ -e "$item" ]] || continue
  if [[ "$item" == "$APP" || "$item" == "$ZIP_PATH" ]]; then
    continue
  fi
  rm -rf "$item"
done
# Also drop stray dotfiles like .DS_Store
rm -f "$DIST/.DS_Store"
shopt -u nullglob
ok

step "Updating share folder…"
mkdir -p "$SHARE_DIST"
# Drop prior Cursor Usage zips/apps so ~/data/bin/dist keeps only the latest.
shopt -s nullglob
for old in "$SHARE_DIST"/Cursor-Usage-*-macOS-*.zip; do
  rm -f "$old"
done
rm -rf "$SHARE_DIST/${APP_NAME}.app"
shopt -u nullglob
cp -f "$ZIP_PATH" "$SHARE_ZIP"
ok "Share copy   →  ${C_DIM}${SHARE_ZIP}${C_RESET}"
finish "$(plist_version "$PLIST")" "$SHARE_ZIP"
tip "Copy to another Mac, unzip, drag to Applications, then Right-click → Open once."
