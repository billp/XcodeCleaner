# XcodeCleaner Architecture Refactor — Design

**Date:** 2026-06-20
**Status:** Approved

## Summary

Restructure the working XcodeCleaner app to **MVVM + protocol-injected services**
with a grouped folder layout, plus best-practice tooling (SwiftLint, SwiftFormat),
a README, and unit tests for the ViewModel and services via fakes. This is a
**behavior-preserving** refactor: the app's features, UI, and delete semantics are
unchanged and verified by the existing test suite.

## Goals

- Introduce protocol seams so the orchestrator and services are unit-testable with
  fakes instead of spawning real `du`/`simctl` processes.
- Organize sources into intent-revealing folders (App/Models/Services/ViewModels/
  Views/Support).
- Add project-level best-practice config and documentation.
- Keep all current behavior and all 8 existing tests green.

## Non-Goals

- Any behavior change (no new targets, no UI changes, no new cleanup actions).
- Heavier architectures (Clean Architecture layers, VIPER, a DI container) — overkill
  at ~350 LOC.
- Adding a confirmation dialog / Dock icon / launch-at-login (out of scope here).

## Current State

8 flat source files under `XcodeCleaner/` (349 LOC): `XcodeCleanerApp`,
`CleanupTarget` (model + `CleanupKind` + `TargetState`), `SimctlParsing`,
`DiskScanner` (contains `Shell` + `ScanError`), `Cleaner`, `AppState`,
`MenuBarView`, `TargetRow`. `AppState` hard-instantiates concrete `DiskScanner()`
and `Cleaner()`; `DiskScanner`/`Cleaner` call the concrete `Shell` directly. No
protocol seams → the orchestrator cannot be tested in isolation.

## Target Folder Structure

Subfolders inside the `PBXFileSystemSynchronizedRootGroup` (`XcodeCleaner/`) are
auto-included recursively, so moving `.swift` files into subfolders needs **no**
pbxproj edit. `Info.plist` and `XcodeCleaner.entitlements` are referenced by
explicit build settings (`INFOPLIST_FILE`, `CODE_SIGN_ENTITLEMENTS`) and by the
synchronized group's `PBXFileSystemSynchronizedBuildFileExceptionSet`; moving them
to `Support/` requires updating those paths (3 references) in `project.pbxproj`.

```
XcodeCleaner/
  App/        XcodeCleanerApp.swift
  Models/     CleanupTarget.swift, CleanupKind.swift, TargetState.swift
  Services/   CommandRunning.swift, DiskScanning.swift, Cleaning.swift, SimctlParsing.swift
  ViewModels/ CleanerViewModel.swift
  Views/      MenuBarView.swift, TargetRow.swift
  Support/    Info.plist, XcodeCleaner.entitlements
XcodeCleanerTests/
  SimctlParsingTests.swift, CleanerTests.swift, ShellTests.swift
  Fakes/      FakeCommandRunner.swift, FakeScanner.swift, FakeCleaner.swift
  CleanerViewModelTests.swift
.swiftlint.yml
.swiftformat
README.md
```

## Architecture: MVVM + Protocol DI

### Protocol seams

- **`CommandRunning`** — `func run(_ launchPath: String, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data)`.
  Concrete `Shell` (moved verbatim from `DiskScanner.swift` into `CommandRunning.swift`)
  conforms. Both `DiskScanner` and `Cleaner` take a `CommandRunning` via init
  (default `Shell()`), replacing direct `Shell.run(...)` static calls with
  `runner.run(...)`.
- **`DiskScanning`** — `func size(of target: CleanupTarget) async -> Result<Int64, Error>`.
  `DiskScanner` conforms (struct → struct with stored `runner`).
- **`Cleaning`** — `func clean(_ target: CleanupTarget) async -> Result<Void, Error>`.
  `Cleaner` conforms (struct → struct with stored `runner`).

`ScanError` moves to `CommandRunning.swift` (or its own small file) since both
services use it; it stays `enum ScanError: Error, Equatable { case process(String) }`.

### ViewModel

`AppState` is renamed to **`CleanerViewModel`** (`@MainActor @Observable final class`),
behavior unchanged. Its `init` becomes:

```swift
init(scanner: DiskScanning = DiskScanner(), cleaner: Cleaning = Cleaner())
```

i.e. it depends on the protocols, not the concrete types, with real defaults so
production code (`MenuBarView`) is unaffected: `@State private var vm = CleanerViewModel()`.
Property/method names (`targets`, `scanAll`, `scan`, `clean`, `totalText`) are
unchanged. `MenuBarView`/`TargetRow` update only to reference `vm`/`CleanerViewModel`
instead of `state`/`AppState`.

## Data Flow

Unchanged: menu open → `vm.scanAll()` → concurrent `scanner.size(of:)` per target →
`target.state` updates on MainActor → rows render size. Clean → `vm.clean(target)` →
`cleaner.clean(target)` → re-scan → `.cleaned`. The only change is that `scanner`
and `cleaner` are now injected protocol values rather than concretely constructed.

## Error Handling

Unchanged. Non-zero process exit → `ScanError.process(stderr)` thrown by the service
→ surfaced as `.error(message)` on the row. The protocol seam does not alter this.

## Testing

- **Existing 8 tests stay green** (they target `SimctlParsing`, `Cleaner.removeDirectoryContents`,
  and the real `Shell`). `ShellTests` continues to exercise the real `Shell` (now a
  `CommandRunning` conformer) against `/bin/sh`.
- **New fakes** (in `XcodeCleanerTests/Fakes/`):
  - `FakeCommandRunner: CommandRunning` — returns scripted `(status, stdout, stderr)`
    keyed by invocation, records calls.
  - `FakeScanner: DiskScanning` and `FakeCleaner: Cleaning` — return scripted results,
    record calls.
- **New tests:**
  - `DiskScanner` + `Cleaner` dispatch tested with `FakeCommandRunner` (e.g. a
    non-zero status from the fake makes `clean`/`size` return `.error`; correct
    argv passed for each `CleanupKind`).
  - `CleanerViewModelTests` — inject `FakeScanner`/`FakeCleaner`; assert state
    transitions: `scan` drives `.scanning`→`.scanned(bytes)`; a scanner failure →
    `.error`; `clean` drives `.cleaning`→`.cleaned(bytes)` (and re-scans); a cleaner
    failure → `.error`; `totalText` sums scanned rows.

Because these tests touch `@MainActor` `CleanerViewModel` and spawn internal
`Task`s, ViewModel tests await the state settling (poll/await the published state)
rather than asserting synchronously.

## Tooling & Docs

- `.swiftlint.yml` — opt-in rule set (line length, force-unwrap discouraged, etc.);
  config only, harmless if SwiftLint isn't installed.
- `.swiftformat` — standard Swift formatting config.
- `README.md` — what the app is, the six targets, the MVVM+DI architecture, and
  build/run/test commands (`xcodebuild ... build|test`, launching the `.app`).

## Migration / Risk

- Behavior-preserving; the test suite is the safety net (run after each step).
- The pbxproj edit (moving Info.plist/entitlements to `Support/`) is the only
  non-source change and the main risk; it's verified by a clean build immediately
  after. If it proves fragile, the fallback is to leave those two files at the
  `XcodeCleaner/` root and keep only the source-folder grouping (the synchronized
  group handles source subfolders without pbxproj changes).
