# Conditional XcodeBuildMCP Row — Design

**Date:** 2026-06-20
**Goal:** The "XcodeBuildMCP workspaces" row appears only when XcodeBuildMCP is installed, instead of always. Other rows are unchanged.

## Context

`CleanerViewModel.init` hardcodes six `CleanupTarget`s, the first being the XcodeBuildMCP workspaces row (`~/Library/Developer/XcodeBuildMCP/workspaces`). For users who never installed XcodeBuildMCP, this row is noise: `DiskScanner` returns `0` bytes for a missing path, so the row just shows "0 bytes" forever with a Clean button that does nothing. We want it to only appear when there's actually something to clean.

**Definition of "installed" (decided during brainstorming):** the row appears iff `~/Library/Developer/XcodeBuildMCP/workspaces` exists on disk. Rationale: it's the exact path we'd clean; if the directory is absent there is nothing to scan or delete, so the row has no purpose.

## Non-goals

- Not changing the other 5 rows. They remain always-shown.
- Not detecting the XcodeBuildMCP MCP server registration or a binary on PATH. The signal is the workspaces directory's existence, nothing else.
- Not making the set of rows dynamic at runtime (e.g. re-checking after the menu opens, or re-checking after a clean). Availability is evaluated once in `init`.
- Not changing `CleanupKind`, `CleanupTarget`, `DiskScanning`, `Cleaning`, or `CommandRunning`.

## Architecture

Following the codebase's just-landed MVVM + protocol-injected-services pattern, introduce a small new service protocol that the ViewModel depends on, with a concrete impl and a test fake. This keeps the ViewModel deterministic and unit-testable for the new behavior, consistent with how `DiskScanning` / `Cleaning` / `CommandRunning` are already wired.

### New: `AvailabilityChecking` protocol

File: `XcodeCleaner/Services/AvailabilityChecking.swift`

```swift
protocol AvailabilityChecking: Sendable {
    func exists(_ path: String) -> Bool
}

struct FileManagerAvailability: AvailabilityChecking {
    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
```

`FileManagerAvailability` is a thin struct over `FileManager.default.fileExists(atPath:)`, tilde-expanded by the caller. It is `Sendable` (struct with no state) and fits beside `CommandRunning`/`DiskScanning`/`Cleaning` in `Services/`.

### Change: `CleanerViewModel`

File: `XcodeCleaner/ViewModels/CleanerViewModel.swift`

Add a fourth injected dependency, `availability: AvailabilityChecking = FileManagerAvailability()`, stored in a private constant. The XcodeBuildMCP target is included in `targets` only when `availability.exists` returns true for the expanded workspaces path. The other five rows are unconditionally appended.

The path string (`"~/Library/Developer/XcodeBuildMCP/workspaces"`) stays as the single source of truth that `DiskScanner` scans and `Cleaner` cleans; the ViewModel expands the tilde once when calling `exists`.

Pseudocode for the new `init` body:

```swift
init(scanner: DiskScanning = DiskScanner(),
     cleaner: Cleaning = Cleaner(),
     availability: AvailabilityChecking = FileManagerAvailability()) {
    self.scanner = scanner
    self.cleaner = cleaner
    self.availability = availability
    var built: [CleanupTarget] = []
    let xbmcpPath = ("~/Library/Developer/XcodeBuildMCP/workspaces" as NSString).expandingTildeInPath
    if availability.exists(xbmcpPath) {
        built.append(CleanupTarget(name: "XcodeBuildMCP workspaces",
                                   kind: .directory(path: "~/Library/Developer/XcodeBuildMCP/workspaces")))
    }
    built.append(CleanupTarget(name: "Xcode DerivedData",
                               kind: .directory(path: "~/Library/Developer/Xcode/DerivedData")))
    built.append(CleanupTarget(name: "SwiftPM cache",
                               kind: .directory(path: "~/Library/Caches/org.swift.swiftpm")))
    built.append(CleanupTarget(name: "iOS DeviceSupport",
                               kind: .directory(path: "~/Library/Developer/Xcode/iOS DeviceSupport")))
    built.append(CleanupTarget(name: "Unused simulators", kind: .unavailableSimulators))
    built.append(CleanupTarget(name: "Unused simulator runtimes", kind: .unusedRuntimes(days: 30)))
    targets = built
}
```

The stored property is `private let availability: AvailabilityChecking`. No other method in the ViewModel changes; `scanAll`, `scan`, `clean`, and `totalText` already operate over `targets` and are agnostic to how many rows there are or which row is first.

### Change: existing ViewModel tests

File: `XcodeCleanerTests/CleanerViewModelTests.swift`

The four existing ViewModel tests select `vm.targets[0]` without asserting its name. Today `targets[0]` is always XcodeBuildMCP. After this change, on machines where the workspaces dir exists (like the dev machine), `targets[0]` is still XcodeBuildMCP; on machines where it doesn't, `targets[0]` becomes "Xcode DerivedData". To keep the tests deterministic and decoupled from the host machine's filesystem, all four existing tests are updated to construct the ViewModel with a `FakeAvailability` that reports `exists = true`, so XcodeBuildMCP is `targets[0]` — preserving the tests' current meaning. No assertion text changes.

### New: `FakeAvailability` fake

File: `XcodeCleanerTests/Fakes/FakeAvailability.swift`

```swift
import Foundation
@testable import XcodeCleaner

final class FakeAvailability: AvailabilityChecking, @unchecked Sendable {
    let existsResult: Bool
    init(existsResult: Bool) { self.existsResult = existsResult }
    func exists(_ path: String) -> Bool { existsResult }
}
```

Stateless (a single `Bool`), so no locking is needed; `@unchecked Sendable` is correct because the type is effectively immutable after init.

### New tests

Append two tests to `CleanerViewModelTests`:

- `testXcodeBuildMCPRowPresentWhenInstalled` — build the ViewModel with `FakeAvailability(existsResult: true)`; assert `vm.targets` contains a target named `"XcodeBuildMCP workspaces"` and that it is the first target.
- `testXcodeBuildMCPRowAbsentWhenNotInstalled` — build with `FakeAvailability(existsResult: false)`; assert no target in `vm.targets` is named `"XcodeBuildMCP workspaces"` and that `vm.targets.first?.name == "Xcode DerivedData"`.

These cover the new behavior directly and run on any host (no real filesystem dependency).

## Data flow

1. `CleanerViewModel.init` receives `availability` (default `FileManagerAvailability()` in production, `FakeAvailability` in tests).
2. Init expands the XcodeBuildMCP path's tilde and asks `availability.exists(path)`.
3. If true, the XcodeBuildMCP target is prepended to `targets`; either way, the other five targets are appended.
4. The rest of the app (`MenuBarView`, `TargetRow`, `scanAll`, `clean`, `totalText`) operates on `targets` and is unchanged.

## Error handling

No new error paths. `FileManager.default.fileExists(atPath:)` is infallible (returns `false` for missing or inaccessible paths). `FakeAvailability.exists` is infallible. The new protocol method is non-throwing.

## Testing

- Existing 15 tests remain green. The 4 ViewModel tests are adjusted to pass `FakeAvailability(existsResult: true)` so they keep selecting XcodeBuildMCP as `targets[0]` regardless of host.
- 2 new ViewModel tests assert presence/absence of the row driven by the fake.
- Total test count goes 15 → 17.

## Build/test commands (unchanged from project convention)

- Build: `xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6` → `** BUILD SUCCEEDED **`.
- Test: `xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10` → `** TEST SUCCEEDED **`.

## Files touched

| File | Change |
|------|--------|
| `XcodeCleaner/Services/AvailabilityChecking.swift` | new — protocol + `FileManagerAvailability` |
| `XcodeCleaner/ViewModels/CleanerViewModel.swift` | add `availability` dep + conditional prepend of XcodeBuildMCP row |
| `XcodeCleanerTests/Fakes/FakeAvailability.swift` | new — test fake |
| `XcodeCleanerTests/CleanerViewModelTests.swift` | pass `FakeAvailability(existsResult: true)` to existing 4 tests; add 2 new tests |

No `pbxproj` edits — `Services/` and `Fakes/` are inside synchronized groups and auto-include new files. No `README.md` targets-table change (the row already documents what it removes; conditional visibility is a UI detail not worth a README edit).
