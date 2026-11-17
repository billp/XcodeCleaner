# Naming Convention Refactoring — Design

**Date:** 2026-06-21
**Status:** Approved (pending user review of written spec)
**Scope:** XcodeCleaner Swift codebase (production + tests)

## Goal

Align naming conventions across the XcodeCleaner codebase with its MVVM + protocol-injected-services architecture. The architecture is sound; eight categories of naming inconsistency were identified. This refactoring applies one decision per category, executed layer-by-layer so the project builds and tests pass after each step.

## Architecture context (summary)

- `App/` — `XcodeCleanerApp` (entry point).
- `Models/` — `CleanupKind`, `CleanupTarget`, `TargetState`.
- `Services/` — protocols with concrete impls: `AvailabilityChecking`/`FileManagerAvailability`, `Cleaning`/`Cleaner`, `CommandRunning`/`Shell`, `DiskScanning`/`DiskScanner`, `Notifying`/`UserNotifier`; plus pure-function enum namespaces `Scheduling` and `SimctlParsing`; plus the cross-cutting error type `ScanError` (currently living inside `CommandRunning.swift`).
- `ViewModels/` — `CleanerViewModel`, `Scheduler`, `SettingsModel` (all `@MainActor @Observable`).
- `Views/` — `MenuBarView`, `MenuRowButtonStyle`, `SettingsView`, `TargetRow`.
- `XcodeCleanerTests/` — unit tests + `Fakes/` (protocol fakes and synchronization gates).

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 15+ synchronized groups), so file renames on disk are picked up automatically — no `project.pbxproj` edits are required.

## Decisions (the rename map)

| Category | Type | Change |
|----------|------|--------|
| A | ViewModel suffix | All `*ViewModel`. `SettingsModel` → `SettingsViewModel`; `Scheduler` → `SchedulerViewModel`. `CleanerViewModel` stays. |
| B | Service protocol/impl pairs | Strict `-ing` protocol + `-er` impl. `Shell` → `CommandRunner`; `FileManagerAvailability` → `AvailabilityChecker`. `Cleaner`, `DiskScanner`, `UserNotifier` stay. Protocols unchanged. |
| C | Pure-function enum | `Scheduling` → `ScheduleMath` (file `Scheduling.swift` → `ScheduleMath.swift`) to avoid confusion with `SchedulerViewModel`. |
| D | Error type | Move `ScanError` out of `CommandRunning.swift` into new `Services/ProcessError.swift`; rename `ScanError` → `ProcessError` (it is thrown from both scanning and cleaning, so "Scan" was misleading). |
| E | Free function | `requestSchedulingAuthorizationIfNeeded(settings:notifier:)` becomes an instance method on `SettingsViewModel`: `settings.requestSchedulingAuthorizationIfNeeded(notifier:)`. Removed from `Notifying.swift`. |
| F | Property | `vm: CleanerViewModel` → `cleaner: CleanerViewModel` in `XcodeCleanerApp`, `MenuBarView`, `SettingsView`. Parallels the existing `settings` and `notifier` role-named properties. |
| G | Test files | `ShellTests` → `CommandRunnerTests`; `SchedulingTests` → `ScheduleMathTests`; `SchedulerTests` → `SchedulerViewModelTests`; `SettingsModelTests` → `SettingsViewModelTests`; delete `NotifyingTests` (move its single test into `SettingsViewModelTests`); split `SimctlParsingTests` — keep the two `SimctlParsing` tests, move the two `CleanupTarget.sizeText` tests into a new `CleanupTargetTests.swift`, delete the placeholder test. |
| H | `TargetState` labels | `.scanned(bytes:)`, `.cleaned(bytes:)`, `.error(message:)`. The case name carries the semantic meaning; the parallel `bytes` labels reinforce that both carry the current byte count of the target. |

## Execution order (layer-by-layer, build + test after each layer)

### Layer 1 — Models

- Edit `XcodeCleaner/Models/TargetState.swift`: add labels to the three cases.
- Update construction sites: `CleanerViewModel.scan` (`.scanned(bytes:)`), `CleanerViewModel.performClean` (`.cleaned(bytes:)`, two `.error(message:)`), `CleanerViewModel.scan` (`.error(message:)`).
- Update tests that construct these cases: `SimctlParsingTests.testSizeTextFormatsScannedBytes` (`t.state = .scanned(bytes: 1_500_000_000)`), `testSizeTextIdleAndScanning` (no change — uses `.scanning`/idle).
- Note: existing pattern-match bindings (`case .scanned(let b), .cleaned(let b):` in `CleanupTarget.sizeBytes`/`sizeText`; `if case .error(let msg)` in `TargetRow`) continue to compile unchanged — labels are required only at construction sites.
- Build + test.

### Layer 2 — Services

Apply the four service-layer renames sequentially. Build + test after each sub-step (or once at the end of layer 2 — they are independent).

2a. **`ScanError` → `ProcessError`, new file.**
   - Create `XcodeCleaner/Services/ProcessError.swift` with `enum ProcessError: Error, Equatable, LocalizedError` (case `process(String)`, same `errorDescription`).
   - Remove `ScanError` from `XcodeCleaner/Services/CommandRunning.swift`.
   - Replace `ScanError.process(...)` → `ProcessError.process(...)` in: `Cleaning.swift` (`runSimctl`), `DiskScanning.swift` (`directoryBytes`, `unusedRuntimeBytes`, `unavailableSimulatorBytes`), `CleanerTests.swift` (`testScanErrorShowsMessageInLocalizedDescription` — also rename the test to `testProcessErrorShowsMessageInLocalizedDescription`), `CleanerViewModelTests.swift` (two references: one in a `FakeScanner` result on line 25, one in a `FakeCleaner` result on line 46).
   - Build + test.

2b. **`Shell` → `CommandRunner`.**
   - In `XcodeCleaner/Services/CommandRunning.swift`: rename `struct Shell: CommandRunning` → `struct CommandRunner: CommandRunning`.
   - Update default-arg construction sites: `Cleaning.swift` (`Cleaner(runner: Shell())` → `CommandRunner()`), `DiskScanning.swift` (`DiskScanner(runner: Shell())` → `CommandRunner()`), `ViewModels/Scheduler.swift` (`runner: CommandRunning = Shell()` → `CommandRunner()`).
   - Update tests: `ShellTests.swift` uses `Shell()` in three places → `CommandRunner()`.
   - Build + test.

2c. **`FileManagerAvailability` → `AvailabilityChecker`.**
   - In `XcodeCleaner/Services/AvailabilityChecking.swift`: rename `struct FileManagerAvailability: AvailabilityChecking` → `struct AvailabilityChecker: AvailabilityChecking`.
   - Update default-arg construction site: `CleanerViewModel.init` (`availability: AvailabilityChecking = FileManagerAvailability()` → `AvailabilityChecker()`).
   - Update tests: `CleanerViewModelTests` does not reference the type by name (uses `FakeAvailability`), so no change. Confirm by grepping.
   - Build + test.

2d. **`Scheduling` → `ScheduleMath` (enum + file).**
   - Rename file `XcodeCleaner/Services/Scheduling.swift` → `XcodeCleaner/Services/ScheduleMath.swift`.
   - Rename `enum Scheduling` → `enum ScheduleMath`.
   - Update call sites: `ViewModels/Scheduler.swift` (`Scheduling.shouldFire`, `Scheduling.isBuildProcess`, `Scheduling.giveUpTime`, `Scheduling.postponedFireTime` → `ScheduleMath.*`).
   - Update tests: `SchedulingTests.swift` references `Scheduling.isBuildProcess`, `Scheduling.shouldFire`, `Scheduling.postponedFireTime`, `Scheduling.giveUpTime` — all → `ScheduleMath.*`. `SchedulerTests.swift` does not reference `Scheduling` directly (only via `Scheduler.tick`).
   - Build + test.

### Layer 3 — ViewModels

3a. **`SettingsModel` → `SettingsViewModel` + absorb the free function.**
   - Rename file `XcodeCleaner/ViewModels/SettingsModel.swift` → `XcodeCleaner/ViewModels/SettingsViewModel.swift`.
   - Rename `final class SettingsModel` → `final class SettingsViewModel`.
   - Add instance method:
     ```swift
     func requestSchedulingAuthorizationIfNeeded(notifier: Notifying) async {
         guard schedulingEnabled else { return }
         await notifier.requestAuthorization()
     }
     ```
   - Remove the free function `requestSchedulingAuthorizationIfNeeded(settings:notifier:)` from `XcodeCleaner/Services/Notifying.swift`. `Notifying.swift` now contains only the `Notifying` protocol and `UserNotifier` struct.
   - Update call sites: `XcodeCleanerApp.init` (`Task { await requestSchedulingAuthorizationIfNeeded(settings: settings, notifier: notifier) }` → `Task { await settings.requestSchedulingAuthorizationIfNeeded(notifier: notifier) }`); `SettingsView` (`settings: SettingsModel` → `SettingsViewModel`); `ViewModels/Scheduler.swift` (`settings: SettingsModel` → `SettingsViewModel`).
   - Update tests: every `SettingsModel(userDefaults: ...)` → `SettingsViewModel(userDefaults: ...)`. Files affected: `SettingsModelTests.swift` (will be renamed in Layer 5), `NotifyingTests.swift` (will be deleted/moved in Layer 5), `SchedulerTests.swift`. Note: `NotifyingTests.testRequestsAuthOnlyWhenSchedulingEnabled` calls the free function — update it to call the instance method now; the file will be deleted in Layer 5 and the test moved.
   - Build + test.

3b. **`Scheduler` → `SchedulerViewModel`.**
   - Rename file `XcodeCleaner/ViewModels/Scheduler.swift` → `XcodeCleaner/ViewModels/SchedulerViewModel.swift`.
   - Rename `final class Scheduler` → `final class SchedulerViewModel`.
   - Update call sites: `XcodeCleanerApp.init` (`scheduler: Scheduler(vm:...)` → `SchedulerViewModel(...)`; property type annotation if any).
   - Update tests: `SchedulerTests.swift` (`Scheduler(vm:...)` → `SchedulerViewModel(vm:...)`).
   - Build + test.

### Layer 4 — Views / App

- `XcodeCleanerApp.swift`: rename `@State private var vm: CleanerViewModel` → `@State private var cleaner: CleanerViewModel`. In `init()`, rename the local `let vm = CleanerViewModel()` → `let cleaner = CleanerViewModel()` and the synthesized backing assignment `_vm = State(initialValue: vm)` → `_cleaner = State(initialValue: cleaner)`. Update all reads: `MenuBarView(vm: vm)` → `MenuBarView(cleaner: cleaner)`, `SettingsView(vm: vm, ...)` → `SettingsView(cleaner: cleaner, ...)`, `vm.isScheduledCleaning` → `cleaner.isScheduledCleaning`, and `Scheduler(vm: vm, ...)` → `SchedulerViewModel(vm: cleaner, ...)` (the `SchedulerViewModel` init parameter label `vm:` is NOT renamed — see Out of scope).
- `MenuBarView.swift`: rename `let vm: CleanerViewModel` → `let cleaner: CleanerViewModel`. Update all reads (`vm.scanAll`, `vm.totalText`, `vm.statusText`, `vm.targets`, `vm.clean(target)`, `vm.isScheduledCleaning`, `vm.isCleaningAll`, `vm.cleanAllCompleted`, `vm.cleanAllTotal`, `vm.cleanAll()`).
- `SettingsView.swift`: rename `let vm: CleanerViewModel` → `let cleaner: CleanerViewModel` (and the matching init parameter `vm:` → `cleaner:` plus `self.vm = vm` → `self.cleaner = cleaner`). Update the `ScheduleTab(vm: vm, ...)` forwarding call to `ScheduleTab(cleaner: cleaner, ...)`.
- `SettingsView.swift`'s nested `ScheduleTab`: rename its `let vm: CleanerViewModel` → `let cleaner: CleanerViewModel` and its body's `vm.targets` → `cleaner.targets`.
- Build + test.

> Note: `Scheduler`'s private stored property `vm` and init parameter `vm:` are NOT renamed (see Out of scope). The call in `XcodeCleanerApp.init` becomes `SchedulerViewModel(vm: cleaner, ...)` — the parameter label stays `vm:`, the argument is the renamed `cleaner` property.

### Layer 5 — Tests restructure

- Rename `XcodeCleanerTests/ShellTests.swift` → `XcodeCleanerTests/CommandRunnerTests.swift`. Update the test class name `ShellTests` → `CommandRunnerTests` and the three `Shell()` call sites → `CommandRunner()` (already done in Layer 2b — verify).
- Rename `XcodeCleanerTests/SchedulingTests.swift` → `XcodeCleanerTests/ScheduleMathTests.swift`. Update class name `SchedulingTests` → `ScheduleMathTests` and all `Scheduling.*` references → `ScheduleMath.*` (already done in Layer 2d — verify).
- Rename `XcodeCleanerTests/SchedulerTests.swift` → `XcodeCleanerTests/SchedulerViewModelTests.swift`. Update class name `SchedulerTests` → `SchedulerViewModelTests` and all `Scheduler(...)` constructor calls → `SchedulerViewModel(...)` (already done in Layer 3b — verify).
- Rename `XcodeCleanerTests/SettingsModelTests.swift` → `XcodeCleanerTests/SettingsViewModelTests.swift`. Update class name `SettingsModelTests` → `SettingsViewModelTests` and all `SettingsModel(...)` → `SettingsViewModel(...)` (already done in Layer 3a — verify).
- Move `testRequestsAuthOnlyWhenSchedulingEnabled` from `NotifyingTests.swift` into `SettingsViewModelTests.swift` (keep the test body, which now calls `settings.requestSchedulingAuthorizationIfNeeded(notifier:)` after Layer 3a). Delete `XcodeCleanerTests/NotifyingTests.swift`.
- Split `XcodeCleanerTests/SimctlParsingTests.swift`:
  - Keep `SimctlParsingTests` class with `testUnusedRuntimeBytesExcludesRecentlyUsed` and `testUnavailableDeviceUDIDs`.
  - Move `testSizeTextFormatsScannedBytes` and `testSizeTextIdleAndScanning` into a new `XcodeCleanerTests/CleanupTargetTests.swift` (new `final class CleanupTargetTests: XCTestCase`). These construct `CleanupTarget(name:kind:)` and set `.scanned(bytes:)` — already updated in Layer 1.
  - Delete `testPlaceholder`.
- Build + test.

## Out of scope

- **Fakes folder names** (`FakeScanner`, `FakeCleaner`, `FakeAvailability`, `FakeCommandRunner`, `FakeNotifier`, `CleanGate`, `BatchCleanGate`) — left as-is. They still conform to the right protocols; tests pass. (User chose "Comprehensive", not "Comprehensive + rename Fakes".)
- **`SimctlParsing` enum** — no naming conflict; untouched. (User's category C flagged only `Scheduling`.)
- **`decode(_:)` private free function** in `DiskScanning.swift` — out of scope.
- **`CleanupTarget` class name / folder placement** — only the three `@MainActor @Observable` classes in `ViewModels/` were in scope for category A. `CleanupTarget` (also `@Observable`, but in `Models/`) keeps its name and location.
- **Access control** on `SchedulerViewModel`'s `lastFired` / `pendingFire` / `originalFire` (currently public `var`, not `private(set)`) — naming-only refactoring; access control is out of scope.
- **`Scheduler`'s private `vm` property and init parameter `vm:`** — the F decision was scoped to "App/Views". `Scheduler` lives in `ViewModels/`, so its `vm` is not renamed. The `XcodeCleanerApp.init` call site becomes `SchedulerViewModel(vm: cleaner, ...)` (parameter label `vm:`, argument `cleaner`).
- **Test-local `let vm = CleanerViewModel(...)` declarations** in `CleanerViewModelTests.swift` and `SchedulerTests.swift` — these are function-local style, not public API. They keep the name `vm`. Reads like `vm.targets[0]`, `vm.scan(target)`, `vm.cleanAll()` in tests are unchanged.
- **`SynchronizedGroupExceptions` in `project.pbxproj`** — no edits needed; Xcode 15+ synchronized groups pick up file renames automatically.

## Verification

After each layer (and after each sub-step within Layer 2 and Layer 3):

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test  CODE_SIGNING_ALLOWED=NO
```

If `swiftformat` and `swiftlint` are installed locally, also run:

```bash
swiftformat . --exclude .build
swiftlint
```

The `.swiftformat` config uses `--self remove`, which will strip any `self.` added during the rename; the `.swiftlint.yml` `identifier_name` rule (min_length: 1) does not restrict any of the new names.

## Risk and rollback

- The main risk is missing a call-site; the Swift compiler will flag each as an "unknown identifier" or "cannot find type" error, making misses obvious. Layering keeps the error surface small per step.
- Each layer is a separate commit (or stash checkpoint), so any layer can be rolled back independently without unwinding the whole refactoring.
- No behavior changes: every rename is purely textual. The instance-method move (E) preserves the exact precondition (`settings.schedulingEnabled`) and effect (`notifier.requestAuthorization()`); the existing test asserts both branches.
