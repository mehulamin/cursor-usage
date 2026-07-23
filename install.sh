#!/usr/bin/env bash
#
# install.sh — Build, install, and launch Cursor Usage
#
# Builds Cursor Usage.app, installs the bundle so Finder treats it like any
# other Mac app, then launches it.
#
# What it does:
#   1. Builds via build.sh into dist/Cursor Usage.app
#   2. Quits any running CursorUsage process (waits for exit)
#   3. Installs that bundle to:
#        /Applications          (default; may prompt for sudo)
#        ~/Applications         (with --user)
#   4. Re-signs the installed app with an ad-hoc signature and launches it
#   5. With --login, also adds it as a Login Item via AppleScript
#   6. Packages a shareable ZIP via package.sh
#
# Usage:
#   ./install.sh                 # → /Applications (may prompt for sudo)
#   ./install.sh --user          # → ~/Applications
#   ./install.sh --login         # also add as a Login Item
#   ./install.sh --user --login
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ui.sh
source "$ROOT/Scripts/ui.sh"

APP_NAME="Cursor Usage"
EXEC_NAME="CursorUsage"
SYSTEM_APP="/Applications/${APP_NAME}.app"
USER_APP="$HOME/Applications/${APP_NAME}.app"
ADD_LOGIN=0
USER_INSTALL=0

for arg in "$@"; do
  case "$arg" in
    --user) USER_INSTALL=1 ;;
    --login) ADD_LOGIN=1 ;;
    -h|--help)
      echo "Usage: $0 [--user] [--login]"
      echo "  (default)  install to /Applications"
      echo "  --user     install to ~/Applications"
      echo "  --login    also add as a Login Item"
      exit 0
      ;;
    *)
      fail "Unknown option: $arg (try --help)"
      ;;
  esac
done

if [[ $USER_INSTALL -eq 1 ]]; then
  APP="$USER_APP"
else
  APP="$SYSTEM_APP"
fi

banner "install"

BUILT="$ROOT/dist/${APP_NAME}.app"
section "build"
if ! nest "$ROOT/build.sh" "$BUILT"; then
  fail "build.sh failed"
fi

section "install"
# Stop any running instance before replacing the bundle — deleting a live .app
# confuses Launch Services and `open` often fails with -600.
quit_running_app() {
  # Match by executable name from any install location (/Applications, ~/Applications, dist/).
  if ! pgrep -xf '.*/CursorUsage$' >/dev/null 2>&1 && ! pgrep -x "$EXEC_NAME" >/dev/null 2>&1; then
    return 0
  fi
  step "Stopping ${APP_NAME} (already running) so the install can replace it…"
  pkill -x "$EXEC_NAME" 2>/dev/null || true
  pkill -f '/CursorUsage$' 2>/dev/null || true
  local i
  for i in $(seq 1 50); do
    pgrep -x "$EXEC_NAME" >/dev/null 2>&1 || pgrep -f '/CursorUsage$' >/dev/null 2>&1 || {
      ok
      return 0
    }
    sleep 0.1
  done
  pkill -9 -x "$EXEC_NAME" 2>/dev/null || true
  pkill -9 -f '/CursorUsage$' 2>/dev/null || true
  sleep 0.2
  ok "Force-stopped ${APP_NAME} so the install can replace it"
}
quit_running_app

install_app() {
  local dest="$1"
  local dest_dir
  dest_dir="$(dirname "$dest")"
  mkdir -p "$dest_dir"
  rm -rf "$dest"
  cp -R "$BUILT" "$dest"
  # Re-sign at the install location (path-sensitive for some Gatekeeper checks)
  codesign --force --deep --sign - "$dest" 2>/dev/null || true
}

step "Installing to ${C_DIM}$(dirname "$APP")${C_RESET}…"
if [[ $USER_INSTALL -eq 1 ]]; then
  install_app "$APP"
else
  if [[ -w /Applications ]]; then
    install_app "$APP"
  else
    warn "Admin privileges required for /Applications"
    # Build a temp script so sudo can copy + resign without prompting twice for each step
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    cat > "$TMP/install-app.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "/Applications"
rm -rf "$APP"
cp -R "$BUILT" "$APP"
codesign --force --deep --sign - "$APP" 2>/dev/null || true
chown -R root:wheel "$APP"
EOF
    chmod +x "$TMP/install-app.sh"
    if ! sudo "$TMP/install-app.sh"; then
      fail "Install failed"
    fi
  fi
fi
ok "Installed  →  ${C_DIM}${APP}${C_RESET}"

# Brief pause so Launch Services picks up the replaced bundle
sleep 0.3
step "Launching…"
open "$APP"
ok

if [[ $ADD_LOGIN -eq 1 ]]; then
  step "Adding Login Item…"
  osascript <<EOF >/dev/null
tell application "System Events"
  set appPath to (POSIX file "$APP") as alias
  set existing to name of every login item
  if existing does not contain "$APP_NAME" then
    make login item at end with properties {path:appPath, hidden:false}
  end if
end tell
EOF
  ok
fi

section "package"
if ! nest "$ROOT/package.sh"; then
  fail "package.sh failed"
fi

finish "$(plist_version "$ROOT/Resources/Info.plist")" "$APP"
if [[ $ADD_LOGIN -eq 0 ]]; then
  tip "Enable Start at Login in Settings → General, or re-run with --login."
fi
