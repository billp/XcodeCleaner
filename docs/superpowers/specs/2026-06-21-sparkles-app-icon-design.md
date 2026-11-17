# Sparkles App Icon — Design

**Date:** 2026-06-21
**Status:** Approved (pending user review of written spec)
**Scope:** Add a custom application icon (sparkles SF Symbol on a macOS squircle background) to the XcodeCleaner .app bundle.

## Goal

The XcodeCleaner app currently has no custom app icon — it uses the default macOS generic app icon. The menu bar extra already uses `Image(systemName: "sparkles")` for its label, but the .app bundle icon (shown in Finder, Launchpad, Force Quit dialog, and the Settings window title bar) is unset. This spec adds a custom app icon that matches the menu-bar symbol: sparkles on a macOS-style squircle background.

## Architecture context

- macOS menu-bar agent app (`LSUIElement = YES`).
- Requires macOS 14+ / Xcode 16+ (per `README.md`).
- Xcode project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 15+ synchronized groups) — new folders under `XcodeCleaner/` are auto-included as build inputs; no `project.pbxproj` file-reference edits needed for adding files.
- No asset catalog exists today (verified: no `Assets.xcassets`, no `AppIcon.appiconset`, no `ASSETCATALOG_COMPILER_APPICON_NAME` build setting).
- App target build configurations live in `XcodeCleaner.xcodeproj/project.pbxproj` under two `XCBuildConfiguration` sections (Debug + Release) for the `XcodeCleaner` target (not the test target).

## Visual design

A single 1024×1024 PNG, rendered programmatically:

- **Squircle background**: macOS app-icon shape — a rounded square with the macOS corner radius (≈ 0.2237 × side length). Filled with a vertical linear gradient from `#3A3A3C` (top) to `#1C1C1E` (bottom) — a graphite tone that reads as "macOS utility" and works in both light and dark mode.
- **Sparkles foreground**: the SF Symbol "sparkles" rendered in the system yellow/gold tint (`#FFD60A`) at approximately 62% of the squircle side, centered. Static render (no variable-value animation needed for a PNG).
- **Aesthetic**: modern flat macOS icon (Big Sur+). No gloss, no drop shadow.

## File structure

New files (committed to the repo, compiled into the app bundle):

- `XcodeCleaner/Assets.xcassets/Contents.json` — asset catalog root manifest (`info` with `author: xcode`, `version: 1`).
- `XcodeCleaner/Assets.xcassets/AppIcon.appiconset/Contents.json` — declares a single 1024×1024 icon entry with `idiom: macosx`, `scale: 1x`, `size: 1024x1024`, `filename: icon_1024.png`. Single-Size idiom (macOS 14+ / Xcode 15+ auto-generates all required sizes from the 1024 source).
- `XcodeCleaner/Assets.xcassets/AppIcon.appiconset/icon_1024.png` — the generated 1024×1024 PNG.

New helper script (development-time, not compiled into the app bundle):

- `scripts/generate_app_icon.swift` — a Swift script that draws the squircle background (NSBezierPath with rounded rect, CoreGraphics gradient fill) and overlays the SF Symbol "sparkles" in `#FFD60A`, then writes a 1024×1024 PNG to `XcodeCleaner/Assets.xcassets/AppIcon.appiconset/icon_1024.png`. Re-runnable any time the icon needs tweaking.

The asset catalog folder is auto-included by the synchronized group — no `project.pbxproj` file-reference additions needed for `Assets.xcassets` or its contents.

## Build settings change

In `XcodeCleaner.xcodeproj/project.pbxproj`, add one line to each of the two app-target `XCBuildConfiguration` sections (Debug and Release — identified by the `XcodeCleaner` product name and the absence of `BUNDLE_LOADER`):

```
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
```

The test target's `XCBuildConfiguration` sections (identified by `BUNDLE_LOADER = "$(TEST_HOST)"`) are NOT modified — tests don't need an app icon.

No `Info.plist` edits: when `ASSETCATALOG_COMPILER_APPICON_NAME` is set, Xcode's asset catalog compiler emits the icon into `Assets.car` and writes the `CFBundleIcon*` keys automatically. The existing `Info.plist` does not need `CFBundleIconFile` or `CFBundleIconName`.

## Verification

```bash
# 1. Generate the icon PNG (writes to Assets.xcassets/AppIcon.appiconset/icon_1024.png)
swift scripts/generate_app_icon.swift

# 2. Build — asset catalog compiles AppIcon into Assets.car
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
# Expected: ** BUILD SUCCEEDED **

# 3. Verify the built .app contains the compiled asset catalog
ls -la ~/Library/Developer/Xcode/DerivedData/XcodeCleaner-*/Build/Products/Debug/XcodeCleaner.app/Contents/Resources/
# Expect: Assets.car present

# 4. Install to /Applications and verify the icon shows in Finder
scripts/install.sh
# Then: in Finder, navigate to /Applications, confirm XcodeCleaner.app shows the sparkles icon
```

## Out of scope

- **Menu bar extra label** (`Image(systemName: "sparkles")` in `XcodeCleanerApp.swift:29`) — unchanged; already the right symbol.
- **Settings window title bar icon** — on macOS the window icon automatically reflects the app icon once `ASSETCATALOG_COMPILER_APPICON_NAME` is set; no separate `NSImage` call or `window.titlebarAppearsTransparent` modifier needed.
- **`Info.plist`** — no edits. `CFBundleIconFile`/`CFBundleIconName` are written by the asset catalog compiler when `ASSETCATALOG_COMPILER_APPICON_NAME` is set.
- **Dark Mode variants** — the graphite squircle works in both light and dark mode; no separate appearance set needed.
- **`AccentColor` asset** — separate concern; the app uses the system default `.accentColor`.
- **Test target** — no icon needed for the test bundle.
- **All-10-sizes PNG set** — the Single-Size 1024 approach (macOS 14+ / Xcode 15+) replaces the traditional 10-PNG set. The asset catalog compiler generates 16/32/128/256/512 at @1x and @2x automatically.

## Risk and rollback

- **Risk**: the asset catalog fails to compile (e.g., wrong `Contents.json` schema, PNG has wrong dimensions, build setting typo). The Swift compiler will not flag this — it surfaces as an `xcodebuild` error during the `CompileXCatalog` step. Mitigation: run `xcodebuild build` after each change and verify `** BUILD SUCCEEDED **`.
- **Rollback**: the change is purely additive (new files + one build setting line per config). Reverting is `git revert <commit>` — no behavioral code changes to unwind.
- **PNG rendering quality**: if the SF Symbol renders poorly at 1024×1024 (e.g., thin strokes alias), the script can be re-run with a larger source size (e.g., 2048×2048) and downsampled. The script is the single source of truth — no hand-edited PNGs.
