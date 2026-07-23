#!/usr/bin/env bash
# Compatibility wrapper — prefer ./build.sh from the repo root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
if [[ "$CONFIGURATION" == "debug" ]]; then
  echo "note: debug builds via SPM are not used by build.sh; running release build" >&2
fi
exec "$ROOT/build.sh"
