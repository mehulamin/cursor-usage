# Cursor Usage (macOS menu bar)

Menu-bar app (no Dock icon) that shows Cursor Pro usage: **Auto**, **API**, **Total**, and days left in the billing cycle.

## Requirements

- macOS 14+
- Swift 5.9+ (Xcode or Command Line Tools)

## Build, install, package

Same workflow as [ma-quick-launch](../ma-quick-launch):

```bash
./build.sh                 # → dist/Cursor Usage.app (auto-bumps patch when Sources/ change)
./install.sh               # build + install to /Applications + launch + package ZIP
./install.sh --user        # → ~/Applications
./install.sh --user --login
./package.sh               # zip dist/Cursor Usage.app → dist/ + ~/data/bin/dist/
```

## Menu

- **Details** — popover with progress, spend, projection, last refresh
- **Settings…** — font size, menu-bar toggles, token, interval, version
- **Quit**

## Auth

1. Paste `WorkosCursorSessionToken` from cursor.com cookies in Settings, or
2. Click **Detect from Cursor** (reads `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`)

## Versioning

- Marketing: `CFBundleShortVersionString` in `Resources/Info.plist` (e.g. `1.0.4`)
- Build: `CFBundleVersion` — always matches the patch digit (`1.0.4` → `4`)
- `./build.sh` hashes `Sources/**/*.swift` into `source.hash` and bumps the patch when sources change
- Commit `Resources/Info.plist` + `source.hash` together so other machines stay in sync
- Shown in Settings as `1.0.4 (4)`

## Project layout

```
Sources/CursorUsage/   # Swift sources
Resources/Info.plist   # LSUIElement + version
Scripts/ui.sh          # shared terminal UI for build/install/package
build.sh / install.sh / package.sh
```
