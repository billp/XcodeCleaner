# Xcode Cleaner

A macOS menu bar app (sparkles icon) that shows the disk usage of Xcode-related caches and lets you reclaim space per-target. Click the icon to list each cache with its current size and an individual **Clean** button. A Settings window adds launch-at-login and weekly scheduled auto-clean with per-target checkboxes.

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
- **Services** — `CommandRunning` (`CommandRunner`) runs processes; `DiskScanning` (`DiskScanner`) computes sizes; `Cleaning` (`Cleaner`) deletes; `SimctlParsing` parses `simctl` JSON; `AvailabilityChecking` (`AvailabilityChecker`) gates the XcodeBuildMCP row; `ScheduleMath` provides pure time-matching and build-process detection functions. Each service is a protocol with a concrete impl and a test fake.
- **ViewModel** (`CleanerViewModel`) — `@MainActor @Observable`; owns the targets and orchestrates scan/clean. Depends on the service protocols (real defaults), so it is unit-tested with fakes.
- **SettingsViewModel** — `@MainActor @Observable`; wraps `UserDefaults` for persistent settings (launch-at-login, scheduling, per-target checkboxes) and `SMAppService` for login-item registration.
- **SchedulerViewModel** — `@MainActor @Observable`; owns a 60s `Timer` and orchestrates weekly scheduled cleaning with a build-process safety guard.
- **Views** (`MenuBarView`, `TargetRow`, `SettingsView`) — the menu bar dropdown and the macOS Settings window.

The app is an agent (`LSUIElement`, no Dock icon) with the App Sandbox disabled (it needs access to `~/Library/Developer` and `xcrun`).

## Settings

Open **Settings…** from the menu bar dropdown (macOS Settings window, two tabs):

- **General** — `Launch at login` toggle (uses `SMAppService`; the app must be running for scheduled cleans to fire, so this is recommended if you enable scheduling). Shows the next scheduled run and selected targets.
- **Schedule** — `Enable scheduled cleaning` toggle, a day-of-week picker, a time picker, and a per-target checklist (each cache row has its own checkbox). At the configured slot each week, XcodeCleaner cleans the checked targets.

**Build-process guard:** before firing a scheduled clean, XcodeCleaner checks for running build processes (`xcodebuild`, `swift`, `swiftc`, `clang`, `clang++`, `ld`, `swift-frontend`). If any are running, the clean is postponed by one hour, repeating hourly up to 24 hours from the original slot — after which it gives up until next week's slot. Cleans never interrupt an in-progress build.

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

> **Launch at login:** `SMAppService` registers the app by its current path, so the app must live in a stable location (e.g. `/Applications`) before you enable **Launch at login** in Settings. An app launched from DerivedData will fail to auto-start because that path changes between builds. To install: copy the built `.app` to `/Applications` (or `~/Applications`), launch it from there, then enable the toggle.
