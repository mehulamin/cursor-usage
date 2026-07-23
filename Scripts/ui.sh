# Shared terminal UI for build.sh / install.sh / package.sh.
# Source from each script after set -euo pipefail:
#   # shellcheck source=Scripts/ui.sh
#   source "$(cd "$(dirname "$0")" && pwd)/Scripts/ui.sh"
#
# Nesting: install.sh runs children via nest() which bumps MA_QL_DEPTH.
# Only depth 0 prints the product banner, final Done, and tips.
#
# Color only when stdout is a TTY (and NO_COLOR is unset).
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""
fi

PRODUCT_NAME="${PRODUCT_NAME:-Cursor Usage}"
MA_QL_DEPTH="${MA_QL_DEPTH:-0}"
_STEP_ACTIVE=0
_STEP_MSG=""
_SECTION=""

# Indent: depth 0 under banner = 1; under a section or nested = 2.
_indent() {
  local i level=$((MA_QL_DEPTH + 1))
  if [[ -n "${_SECTION}" && "$MA_QL_DEPTH" -eq 0 ]]; then
    level=2
  fi
  for ((i = 0; i < level; i++)); do printf '   '; done
}

# Root only: ◆  Cursor Usage  ·  build|install|package
banner() {
  _SECTION=""
  if [[ "$MA_QL_DEPTH" -eq 0 ]]; then
    printf '%s◆%s  %s%s%s  ·  %s%s%s\n\n' \
      "$C_CYAN$C_BOLD" "$C_RESET" "$C_BOLD" "$PRODUCT_NAME" "$C_RESET" "$C_CYAN" "$*" "$C_RESET"
    _AFTER_BANNER=1
  else
    _AFTER_BANNER=0
  fi
}

# Parent phase marker: ▸ build|install|package
section() {
  _SECTION="$*"
  if [[ "${_AFTER_BANNER:-0}" -eq 1 ]]; then
    _AFTER_BANNER=0
  else
    printf '\n'
  fi
  printf '%s   ▸%s %s%s%s\n' "$C_CYAN$C_BOLD" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"
}

# Dim artifact / result path under the current phase.
artifact() {
  _indent
  printf '%s→%s %s\n' "$C_DIM" "$C_RESET" "$*"
}

# In-progress step (no newline on a TTY). Finish with ok / fail.
step() {
  _STEP_MSG="$*"
  if [[ -t 1 ]]; then
    _indent
    printf '%s→%s %s' "$C_CYAN" "$C_RESET" "$*"
    _STEP_ACTIVE=1
  else
    _STEP_ACTIVE=0
  fi
}

# Complete the open step on the same line. With args, replaces the step text.
ok() {
  local msg="${*:-${_STEP_MSG:-}}"
  if [[ "${_STEP_ACTIVE:-0}" -eq 1 ]]; then
    printf '\r\033[K'
    _indent
    printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$msg"
  else
    _indent
    printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$msg"
  fi
  _STEP_ACTIVE=0
  _STEP_MSG=""
}

warn() {
  if [[ "${_STEP_ACTIVE:-0}" -eq 1 ]]; then
    printf '\n'
    _STEP_ACTIVE=0
    _STEP_MSG=""
  fi
  _indent
  printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"
}

fail() {
  if [[ "${_STEP_ACTIVE:-0}" -eq 1 ]]; then
    printf '\r\033[K'
    _indent
    printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "${_STEP_MSG}" >&2
    _STEP_ACTIVE=0
    _STEP_MSG=""
  fi
  _indent
  printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
  exit 1
}

# Marketing + build number from an Info.plist → e.g. "1.0.0 (1)"
plist_version() {
  local plist="$1"
  local ver build
  ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo "?")"
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo "?")"
  printf '%s (%s)' "$ver" "$build"
}

# Root: ◆ Done · vX.Y.Z (N)  then dim path. Nested: dim "v… → path".
# Usage: finish VERSION PATH
finish() {
  local ver="$1"
  local path="${2:-}"
  if [[ "$MA_QL_DEPTH" -eq 0 ]]; then
    printf '\n%s◆%s  %sDone%s  ·  %sv%s%s\n' \
      "$C_GREEN$C_BOLD" "$C_RESET" "$C_GREEN$C_BOLD" "$C_RESET" \
      "$C_BOLD" "$ver" "$C_RESET"
    if [[ -n "$path" ]]; then
      printf '%s   %s%s\n' "$C_DIM" "$path" "$C_RESET"
    fi
  else
    if [[ -n "$path" ]]; then
      artifact "v${ver}  ·  ${path}"
    else
      artifact "v${ver}"
    fi
  fi
}

tip() {
  [[ "$MA_QL_DEPTH" -eq 0 ]] || return 0
  printf '%s   %s%s\n' "$C_DIM" "$*" "$C_RESET"
}

# Run a child script one depth deeper (suppresses its banner/Done/tips).
nest() {
  MA_QL_DEPTH=$((MA_QL_DEPTH + 1)) "$@"
}
