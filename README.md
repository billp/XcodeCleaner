# Xcode Cleaner

A macOS menu bar app that shows the disk usage of Xcode-related caches and lets you reclaim space per-target. A trash icon sits in the menu bar; clicking it lists each cache with its current size and an individual **Clean** button that shows live progress.

## Targets cleaned

| Row | What it removes |
|-----|-----------------|
| XcodeBuildMCP workspaces | `~/Library/Developer/XcodeBuildMCP/workspaces` contents |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` contents |
| SwiftPM cache | `~/Library/Caches/org.swift.swiftpm` contents |
| iOS DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport` contents |
| Unused simulators | `xcrun simctl delete unavailable` |
| Unused simulator runtimes | `xcrun simctl runtime delete --notUsedSinceDays 30` |

> Clean buttons delete immediately — there is no confirmation dialog.

## Architecture

MVVM with protocol-injected services:

- **Models** (`CleanupTarget`, `CleanupKind`, `TargetState`) — what to clean and per-row state.
- **Services** — `CommandRunning` (`Shell`) runs processes; `DiskScanning` (`DiskScanner`) computes sizes; `Cleaning` (`Cleaner`) deletes; `SimctlParsing` parses `simctl` JSON. Each service is a protocol with a concrete impl and a test fake.
- **ViewModel** (`CleanerViewModel`) — `@MainActor @Observable`; owns the targets and orchestrates scan/clean. Depends on the service protocols (real defaults), so it is unit-tested with fakes.
- **Views** (`MenuBarView`, `TargetRow`) — the menu bar dropdown.

The app is an agent (`LSUIElement`, no Dock icon) with the App Sandbox disabled (it needs access to `~/Library/Developer` and `xcrun`).

## Build / run / test

```bash
# Build
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO

# Test
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO

# Run the built app
open ~/Library/Developer/Xcode/DerivedData/XcodeCleaner-*/Build/Products/Debug/XcodeCleaner.app
```

Requirements: macOS 14+, Xcode 16+ (developed on Xcode 26.3 / Swift 6.2).
