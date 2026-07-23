#!/usr/bin/env bash
# Manual build-number bump. Prefer ./build.sh — it auto-bumps the patch
# version when Sources/ change (via source.hash).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"

if [[ ! -f "$PLIST" ]]; then
  echo "error: Info.plist not found at $PLIST" >&2
  exit 1
fi

ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
IFS=. read -r major minor patch <<< "$ver"
major="${major:-0}"
minor="${minor:-0}"
patch="${patch:-0}"
patch=$((patch + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${major}.${minor}.${patch}" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${patch}" "$PLIST"
# Force next build.sh to treat sources as changed relative to old hash only if needed —
# clear hash so the next build re-seeds without double-bumping.
rm -f "$ROOT/source.hash"
echo "Version bumped → ${major}.${minor}.${patch} (${patch})"
echo "Cleared source.hash — next ./build.sh will re-seed it."
