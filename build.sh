#!/usr/bin/env bash
# Build Cursor Usage.app — a self-contained macOS menu-bar app bundle.
#
# Usage:
#   ./build.sh                  # → dist/Cursor Usage.app
#   ./build.sh /path/to/App.app # custom destination
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ui.sh
source "$ROOT/Scripts/ui.sh"

APP_NAME="Cursor Usage"
EXEC_NAME="CursorUsage"
DIST="$ROOT/dist"
DEST="${1:-$DIST/${APP_NAME}.app}"
CONTENTS="$DEST/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
ICON_ICNS="$ROOT/Resources/AppIcon.icns"
PLIST="$ROOT/Resources/Info.plist"
# Tracked in git so every machine shares the same “last built sources” watermark.
HASH_FILE="$ROOT/source.hash"

# Portable content hash of Sources/**/*.swift (relative paths — stable across machines).
sources_hash() {
  local f rel
  {
    while IFS= read -r f; do
      rel="${f#"$ROOT"/}"
      # "content-hash  relative/path" — do not include absolute paths.
      printf '%s  %s\n' "$(shasum -a 256 < "$f" | awk '{ print $1 }')" "$rel"
    done < <(find "$ROOT/Sources" -name '*.swift' -type f | LC_ALL=C sort)
  } | shasum -a 256 | awk '{ print $1 }'
}

# If Sources/ changed since the last recorded hash, bump CFBundleShortVersionString
# patch (1.0.0 → 1.0.1). CFBundleVersion always matches the patch digit (1.0.3 → 3).
# Missing source.hash: seed baseline only (commit it so other machines can bump).
bump_version_if_sources_changed() {
  local new_hash old_hash ver major minor patch
  new_hash="$(sources_hash)"
  old_hash=""
  [[ -f "$HASH_FILE" ]] && old_hash="$(tr -d '[:space:]' < "$HASH_FILE")"
  if [[ ! -f "$HASH_FILE" ]]; then
    printf '%s\n' "$new_hash" > "$HASH_FILE"
    sync_build_to_patch
    tip "Seeded source.hash — commit it so other machines share build numbering."
    return 0
  fi
  if [[ "$new_hash" == "$old_hash" ]]; then
    sync_build_to_patch
    return 0
  fi
  ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
  IFS=. read -r major minor patch <<< "$ver"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"
  patch=$((patch + 1))
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${major}.${minor}.${patch}" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${patch}" "$PLIST"
  printf '%s\n' "$new_hash" > "$HASH_FILE"
  # Drop the old local-only watermark if present.
  rm -f "$DIST/.source-hash"
  ok "Version bumped → ${major}.${minor}.${patch} (${patch})"
  tip "Commit Resources/Info.plist + source.hash so other machines stay in sync."
}

# Keep CFBundleVersion equal to the patch digit of CFBundleShortVersionString.
sync_build_to_patch() {
  local ver major minor patch build
  ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
  IFS=. read -r major minor patch <<< "$ver"
  patch="${patch:-0}"
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
  if [[ "$build" != "$patch" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${patch}" "$PLIST"
    ok "Build aligned → ${ver} (${patch})"
  fi
}

banner "build"
[[ -f "$PLIST" ]] || fail "Missing ${PLIST}"
bump_version_if_sources_changed

step "Building → ${C_DIM}${DEST}${C_RESET}"
rm -rf "$DEST"
mkdir -p "$MACOS" "$RESOURCES_DIR"
ok

step "Compiling (swift build -c release)…"
(
  cd "$ROOT"
  swift build -c release
) >/dev/null
ok

BIN="$ROOT/.build/release/$EXEC_NAME"
[[ -x "$BIN" ]] || fail "Expected binary at ${BIN}"

step "Assembling app bundle…"
cp "$BIN" "$MACOS/$EXEC_NAME"
chmod +x "$MACOS/$EXEC_NAME"
cp "$PLIST" "$CONTENTS/Info.plist"
# Classic bundle marker (APPL + creator; ???? = unregistered)
printf 'APPL????' > "$CONTENTS/PkgInfo"

if [[ -f "$ICON_ICNS" ]]; then
  cp "$ICON_ICNS" "$RESOURCES_DIR/AppIcon.icns"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$CONTENTS/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile AppIcon' "$CONTENTS/Info.plist"
fi
ok

# Ad-hoc sign so macOS Gatekeeper is happier for local use
step "Ad-hoc codesign…"
codesign --force --deep --sign - "$DEST" 2>/dev/null || true
ok

# Keep only the app we just built inside dist/ (drop prior zips / stale bundles).
if [[ "$DEST" == "$DIST"/* ]]; then
  step "Cleaning older builds in dist/…"
  shopt -s nullglob
  for item in "$DIST"/* "$DIST"/.[!.]* "$DIST"/..?*; do
    [[ -e "$item" ]] || continue
    # Keep the freshly built app; remove everything else (old zips, stale .app names, .DS_Store).
    if [[ "$item" == "$DEST" ]]; then
      continue
    fi
    rm -rf "$item"
  done
  shopt -u nullglob
  ok
fi

finish "$(plist_version "$PLIST")" "$DEST"
tip "Install: ./install.sh   or   ./install.sh --user"
