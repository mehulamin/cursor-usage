# Agent notes — Cursor Usage

- Prefer `./build.sh` / `./install.sh` / `./package.sh` (same pattern as ma-quick-launch).
- **After any code changes, always run `./install.sh`** so `/Applications/Cursor Usage.app` is rebuilt, replaced, and relaunched. Do not leave the user on a stale build.
- `./build.sh` auto-bumps the patch version when `Sources/**/*.swift` change (via `source.hash`). Commit `Resources/Info.plist` + `source.hash` together.
- Do not hand-edit `CFBundleVersion` out of sync with the patch digit of `CFBundleShortVersionString`.
- Manual bump only if needed: `./Scripts/bump-build.sh`.
- Usage fetch logic mirrors `/Users/mamin/Code/cursor-usage-bar-extension/extension.js`.
