# Naming Convention Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align naming conventions across the XcodeCleaner codebase with its MVVM + protocol-injected-services architecture — eight categories of rename, executed layer-by-layer with build + test after each.

**Architecture:** Pure rename refactoring — no behavior changes. Existing tests are the safety net and must stay green after every task. The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 15+ synchronized groups), so file renames on disk are picked up automatically — no `project.pbxproj` edits needed.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, ServiceManagement, UserNotifications. Build/test via `xcodebuild`. Lint via `swiftformat` + `swiftlint` (optional, if installed).

**Spec:** `docs/superpowers/specs/2026-06-21-naming-convention-refactoring-design.md`

---

## File Structure

### Files created
- `XcodeCleaner/Services/ProcessError.swift` — the `ProcessError` enum (moved + renamed from `ScanError` in `CommandRunning.swift`).
- `XcodeCleanerTests/CleanupTargetTests.swift` — tests for `CleanupTarget.sizeText`/`sizeBytes` (split from `SimctlParsingTests.swift`).

### Files renamed (git mv)
- `XcodeCleaner/Services/Scheduling.swift` → `ScheduleMath.swift`
- `XcodeCleaner/ViewModels/SettingsModel.swift` → `SettingsViewModel.swift`
- `XcodeCleaner/ViewModels/Scheduler.swift` → `SchedulerViewModel.swift`
- `XcodeCleanerTests/ShellTests.swift` → `CommandRunnerTests.swift`
- `XcodeCleanerTests/SchedulingTests.swift` → `ScheduleMathTests.swift`
- `XcodeCleanerTests/SchedulerTests.swift` → `SchedulerViewModelTests.swift`
- `XcodeCleanerTests/SettingsModelTests.swift` → `SettingsViewModelTests.swift`

### Files deleted
- `XcodeCleanerTests/NotifyingTests.swift` — its single test moves to `SettingsViewModelTests.swift`.

### Files modified (content only)
- `XcodeCleaner/Models/TargetState.swift` — add associated-value labels.
- `XcodeCleaner/Services/CommandRunning.swift` — remove `ScanError`, rename `Shell` → `CommandRunner`.
- `XcodeCleaner/Services/Cleaning.swift` — `ScanError` → `ProcessError`, `Shell()` → `CommandRunner()`.
- `XcodeCleaner/Services/DiskScanning.swift` — `ScanError` → `ProcessError`, `Shell()` → `CommandRunner()`.
- `XcodeCleaner/Services/Notifying.swift` — remove free function `requestSchedulingAuthorizationIfNeeded`.
- `XcodeCleaner/Services/AvailabilityChecking.swift` — rename `FileManagerAvailability` → `AvailabilityChecker`.
- `XcodeCleaner/ViewModels/CleanerViewModel.swift` — `TargetState` labels, `FileManagerAvailability()` → `AvailabilityChecker()`.
- `XcodeCleaner/ViewModels/Scheduler.swift` (→ `SchedulerViewModel.swift`) — `ScheduleMath.*`, `SettingsViewModel`, class rename.
- `XcodeCleaner/ViewModels/SettingsModel.swift` (→ `SettingsViewModel.swift`) — class rename, absorb auth-request method.
- `XcodeCleaner/App/XcodeCleanerApp.swift` — type renames, `vm` → `cleaner`.
- `XcodeCleaner/Views/MenuBarView.swift` — `vm` → `cleaner`.
- `XcodeCleaner/Views/SettingsView.swift` — `SettingsModel` → `SettingsViewModel`, `vm` → `cleaner`.
- `XcodeCleanerTests/CleanerTests.swift` — `ScanError` → `ProcessError`.
- `XcodeCleanerTests/CleanerViewModelTests.swift` — `TargetState` labels, `ScanError` → `ProcessError`.
- `XcodeCleanerTests/SimctlParsingTests.swift` — `TargetState` label, split out `sizeText` tests, delete placeholder.

---

## Verification commands

Use these after each task. The build is fast; the test suite is the safety net.

```bash
# Build
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO

# Test
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

**Expected build output:** `** BUILD SUCCEEDED **`
**Expected test output:** `** TEST SUCCEEDED **` (or `Test Suite 'All tests' passed`)

If `swiftformat` and `swiftlint` are installed locally, also run after each task:

```bash
swiftformat . --exclude .build
swiftlint
```

---

## Task 1: Add labels to TargetState associated values (Layer 1 — Models)

**Files:**
- Modify: `XcodeCleaner/Models/TargetState.swift`
- Modify: `XcodeCleaner/ViewModels/CleanerViewModel.swift:48-49,92,95,99`
- Modify: `XcodeCleanerTests/SimctlParsingTests.swift:9`

- [ ] **Step 1: Add labels to TargetState.swift**

Replace the entire content of `XcodeCleaner/Models/TargetState.swift`:

```swift
import Foundation

enum TargetState: Equatable {
    case idle
    case scanning
    case scanned(bytes: Int64)
    case cleaning
    case cleaned(bytes: Int64)
    case error(message: String)
}
```

- [ ] **Step 2: Update construction sites in CleanerViewModel.swift**

In `XcodeCleaner/ViewModels/CleanerViewModel.swift`, make these five replacements:

Line 48:
```swift
// old
case .success(let bytes): target.state = .scanned(bytes)
// new
case .success(let bytes): target.state = .scanned(bytes: bytes)
```

Line 49:
```swift
// old
case .failure(let err): target.state = .error(err.localizedDescription)
// new
case .failure(let err): target.state = .error(message: err.localizedDescription)
```

Line 92:
```swift
// old
target.state = .cleaned(after)
// new
target.state = .cleaned(bytes: after)
```

Line 95:
```swift
// old
target.state = .error(err.localizedDescription)
// new
target.state = .error(message: err.localizedDescription)
```

Line 99:
```swift
// old
target.state = .error(err.localizedDescription)
// new
target.state = .error(message: err.localizedDescription)
```

> **Note:** Pattern-match sites (`case .scanned(let b), .cleaned(let b):` in `CleanupTarget.swift:17,27` and `if case .error(let msg)` in `TargetRow.swift:11`, plus `if case .scanned =`/`if case .error =`/`if case .cleaned =` in `CleanerViewModelTests.swift`) do NOT need changes — Swift allows omitting labels in pattern matching.

- [ ] **Step 3: Update construction site in SimctlParsingTests.swift**

In `XcodeCleanerTests/SimctlParsingTests.swift`, line 9:

```swift
// old
t.state = .scanned(1_500_000_000)
// new
t.state = .scanned(bytes: 1_500_000_000)
```

- [ ] **Step 4: Build + test**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add XcodeCleaner/Models/TargetState.swift XcodeCleaner/ViewModels/CleanerViewModel.swift XcodeCleanerTests/SimctlParsingTests.swift
git commit -m "refactor: add labels to TargetState associated values"
```

---

## Task 2: Move ScanError to ProcessError.swift and rename (Layer 2a — Services)

**Files:**
- Create: `XcodeCleaner/Services/ProcessError.swift`
- Modify: `XcodeCleaner/Services/CommandRunning.swift:3-8`
- Modify: `XcodeCleaner/Services/Cleaning.swift:36`
- Modify: `XcodeCleaner/Services/DiskScanning.swift:45,54,64`
- Modify: `XcodeCleanerTests/CleanerTests.swift:89-91`
- Modify: `XcodeCleanerTests/CleanerViewModelTests.swift:25,46`

- [ ] **Step 1: Create ProcessError.swift**

Create `XcodeCleaner/Services/ProcessError.swift`:

```swift
import Foundation

enum ProcessError: Error, Equatable, LocalizedError {
    case process(String)
    var errorDescription: String? {
        switch self { case .process(let message): return message }
    }
}
```

- [ ] **Step 2: Remove ScanError from CommandRunning.swift**

In `XcodeCleaner/Services/CommandRunning.swift`, remove lines 3–8 (the `ScanError` enum and the blank line after it). The file should start with:

```swift
import Foundation

protocol CommandRunning: Sendable {
    func run(_ launchPath: String, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data)
}
```

- [ ] **Step 3: Update Cleaning.swift**

In `XcodeCleaner/Services/Cleaning.swift`, line 36:

```swift
// old
throw ScanError.process(stderr.isEmpty ? "exit \(status)" : stderr)
// new
throw ProcessError.process(stderr.isEmpty ? "exit \(status)" : stderr)
```

- [ ] **Step 4: Update DiskScanning.swift**

In `XcodeCleaner/Services/DiskScanning.swift`, three identical replacements at lines 45, 54, and 64:

```swift
// old
throw ScanError.process(msg.isEmpty ? "exit \(status)" : msg)
// new
throw ProcessError.process(msg.isEmpty ? "exit \(status)" : msg)
```

- [ ] **Step 5: Update CleanerTests.swift**

In `XcodeCleanerTests/CleanerTests.swift`, lines 89–91:

```swift
// old
func testScanErrorShowsMessageInLocalizedDescription() {
    XCTAssertEqual(ScanError.process("boom").localizedDescription, "boom")
}
// new
func testProcessErrorShowsMessageInLocalizedDescription() {
    XCTAssertEqual(ProcessError.process("boom").localizedDescription, "boom")
}
```

- [ ] **Step 6: Update CleanerViewModelTests.swift**

In `XcodeCleanerTests/CleanerViewModelTests.swift`, two replacements:

Line 25:
```swift
// old
let vm = CleanerViewModel(scanner: FakeScanner(result: .failure(ScanError.process("x"))),
// new
let vm = CleanerViewModel(scanner: FakeScanner(result: .failure(ProcessError.process("x"))),
```

Line 46:
```swift
// old
cleaner: FakeCleaner(result: .failure(ScanError.process("y"))),
// new
cleaner: FakeCleaner(result: .failure(ProcessError.process("y"))),
```

- [ ] **Step 7: Build + test**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add XcodeCleaner/Services/ProcessError.swift XcodeCleaner/Services/CommandRunning.swift XcodeCleaner/Services/Cleaning.swift XcodeCleaner/Services/DiskScanning.swift XcodeCleanerTests/CleanerTests.swift XcodeCleanerTests/CleanerViewModelTests.swift
git commit -m "refactor: move ScanError to ProcessError.swift and rename to ProcessError"
```

---

## Task 3: Rename Shell to CommandRunner (Layer 2b — Services)

**Files:**
- Modify: `XcodeCleaner/Services/CommandRunning.swift:14`
- Modify: `XcodeCleaner/Services/Cleaning.swift:10`
- Modify: `XcodeCleaner/Services/DiskScanning.swift:12`
- Modify: `XcodeCleaner/ViewModels/Scheduler.swift:17`
- Modify: `XcodeCleanerTests/ShellTests.swift:6,13,24`

- [ ] **Step 1: Rename the struct in CommandRunning.swift**

In `XcodeCleaner/Services/CommandRunning.swift`, line 14:

```swift
// old
struct Shell: CommandRunning {
// new
struct CommandRunner: CommandRunning {
```

- [ ] **Step 2: Update default-arg in Cleaning.swift**

In `XcodeCleaner/Services/Cleaning.swift`, line 10:

```swift
// old
init(runner: CommandRunning = Shell()) {
// new
init(runner: CommandRunning = CommandRunner()) {
```

- [ ] **Step 3: Update default-arg in DiskScanning.swift**

In `XcodeCleaner/Services/DiskScanning.swift`, line 12:

```swift
// old
init(runner: CommandRunning = Shell()) {
// new
init(runner: CommandRunning = CommandRunner()) {
```

- [ ] **Step 4: Update default-arg in Scheduler.swift**

In `XcodeCleaner/ViewModels/Scheduler.swift`, line 17:

```swift
// old
runner: CommandRunning = Shell(), notifier: Notifying = UserNotifier()) {
// new
runner: CommandRunning = CommandRunner(), notifier: Notifying = UserNotifier()) {
```

- [ ] **Step 5: Update ShellTests.swift call sites**

In `XcodeCleanerTests/ShellTests.swift`, three replacements at lines 6, 13, and 24:

```swift
// old (line 6)
let (status, _, stderr) = try await Shell().run("/bin/sh", ["-c", "echo boom 1>&2; exit 3"])
// new
let (status, _, stderr) = try await CommandRunner().run("/bin/sh", ["-c", "echo boom 1>&2; exit 3"])

// old (line 13)
let (status, stdout, _) = try await Shell().run("/bin/echo", ["hello"])
// new
let (status, stdout, _) = try await CommandRunner().run("/bin/echo", ["hello"])

// old (line 24)
let (status, stdout, _) = try await Shell().run("/bin/sh", ["-c", "yes 1234567890 | head -n 20000"])
// new
let (status, stdout, _) = try await CommandRunner().run("/bin/sh", ["-c", "yes 1234567890 | head -n 20000"])
```

- [ ] **Step 6: Build + test**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add XcodeCleaner/Services/CommandRunning.swift XcodeCleaner/Services/Cleaning.swift XcodeCleaner/Services/DiskScanning.swift XcodeCleaner/ViewModels/Scheduler.swift XcodeCleanerTests/ShellTests.swift
git commit -m "refactor: rename Shell to CommandRunner"
```

---

## Task 4: Rename FileManagerAvailability to AvailabilityChecker (Layer 2c — Services)

**Files:**
- Modify: `XcodeCleaner/Services/AvailabilityChecking.swift:7`
- Modify: `XcodeCleaner/ViewModels/CleanerViewModel.swift:18`

- [ ] **Step 1: Rename the struct in AvailabilityChecking.swift**

In `XcodeCleaner/Services/AvailabilityChecking.swift`, line 7:

```swift
// old
struct FileManagerAvailability: AvailabilityChecking {
// new
struct AvailabilityChecker: AvailabilityChecking {
```

- [ ] **Step 2: Update default-arg in CleanerViewModel.swift**

In `XcodeCleaner/ViewModels/CleanerViewModel.swift`, line 18:

```swift
// old
availability: AvailabilityChecking = FileManagerAvailability()) {
// new
availability: AvailabilityChecking = AvailabilityChecker()) {
```

- [ ] **Step 3: Build + test**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`

> **Note:** Tests use `FakeAvailability`, not the concrete type, so no test edits needed.

- [ ] **Step 4: Commit**

```bash
git add XcodeCleaner/Services/AvailabilityChecking.swift XcodeCleaner/ViewModels/CleanerViewModel.swift
git commit -m "refactor: rename FileManagerAvailability to AvailabilityChecker"
```

---

## Task 5: Rename Scheduling enum to ScheduleMath (Layer 2d — Services)

**Files:**
- Rename: `XcodeCleaner/Services/Scheduling.swift` → `ScheduleMath.swift`
- Modify: `XcodeCleaner/ViewModels/Scheduler.swift:39,61,67,71`
- Modify: `XcodeCleanerTests/SchedulingTests.swift:8-14,24,34,46,56,65,78,91`

- [ ] **Step 1: Rename the file**

```bash
git mv XcodeCleaner/Services/Scheduling.swift XcodeCleaner/Services/ScheduleMath.swift
```

- [ ] **Step 2: Rename the enum in ScheduleMath.swift**

In `XcodeCleaner/Services/ScheduleMath.swift`, line 3:

```swift
// old
enum Scheduling {
// new
enum ScheduleMath {
```

- [ ] **Step 3: Update call sites in Scheduler.swift**

In `XcodeCleaner/ViewModels/Scheduler.swift`, four replacements:

Line 39:
```swift
// old
guard Scheduling.shouldFire(
// new
guard ScheduleMath.shouldFire(
```

Line 61:
```swift
// old
.contains { Scheduling.isBuildProcess($0) }
// new
.contains { ScheduleMath.isBuildProcess($0) }
```

Line 67:
```swift
// old
if let original = originalFire, now >= Scheduling.giveUpTime(originalFire: original) {
// new
if let original = originalFire, now >= ScheduleMath.giveUpTime(originalFire: original) {
```

Line 71:
```swift
// old
pendingFire = Scheduling.postponedFireTime(from: now)
// new
pendingFire = ScheduleMath.postponedFireTime(from: now)
```

- [ ] **Step 4: Update SchedulingTests.swift**

In `XcodeCleanerTests/SchedulingTests.swift`, replace every `Scheduling.` with `ScheduleMath.`. There are 14 occurrences across lines 8–14, 24, 34, 46, 56, 65, 78, and 91. The replacements are all the same pattern:

```swift
// old
Scheduling.isBuildProcess(...)
Scheduling.shouldFire(...)
Scheduling.postponedFireTime(...)
Scheduling.giveUpTime(...)
// new
ScheduleMath.isBuildProcess(...)
ScheduleMath.shouldFire(...)
ScheduleMath.postponedFireTime(...)
ScheduleMath.giveUpTime(...)
```

> **Note:** Do NOT rename the test class `SchedulingTests` or the file yet — that happens in Task 12.

- [ ] **Step 5: Build + test**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add XcodeCleaner/Services/ScheduleMath.swift XcodeCleaner/ViewModels/Scheduler.swift XcodeCleanerTests/SchedulingTests.swift
git commit -m "refactor: rename Scheduling enum to ScheduleMath"
```

---

## Task 6: Rename SettingsModel to SettingsViewModel and absorb auth-request method (Layer 3a — ViewModels)

**Files:**
- Rename: `XcodeCleaner/ViewModels/SettingsModel.swift` → `SettingsViewModel.swift`
- Modify: `XcodeCleaner/Services/Notifying.swift:27-34`
- Modify: `XcodeCleaner/App/XcodeCleanerApp.swift:7,14,22`
- Modify: `XcodeCleaner/Views/SettingsView.swift:5,8,26,70`
- Modify: `XcodeCleaner/ViewModels/Scheduler.swift:7,16`
- Modify: `XcodeCleanerTests/SettingsModelTests.swift` (all `SettingsModel` → `SettingsViewModel`)
- Modify: `XcodeCleanerTests/NotifyingTests.swift:12,16,20`
- Modify: `XcodeCleanerTests/SchedulerTests.swift` (all `SettingsModel` → `SettingsViewModel`)

- [ ] **Step 1: Rename the file**

```bash
git mv XcodeCleaner/ViewModels/SettingsModel.swift XcodeCleaner/ViewModels/SettingsViewModel.swift
```

- [ ] **Step 2: Rename the class in SettingsViewModel.swift**

In `XcodeCleaner/ViewModels/SettingsViewModel.swift`, line 6:

```swift
// old
final class SettingsModel {
// new
final class SettingsViewModel {
```

- [ ] **Step 3: Add the instance method to SettingsViewModel.swift**

Add this method inside the `SettingsViewModel` class (after `reconcileLaunchAtLogin()`, before `var schedulingEnabled`):

```swift
    /// Requests notification authorization at launch when scheduling is already
    /// enabled. The Schedule toggle's onChange only fires on a fresh toggle, so a
    /// persisted-enabled schedule would otherwise never (re)request authorization.
    func requestSchedulingAuthorizationIfNeeded(notifier: Notifying) async {
        guard schedulingEnabled else { return }
        await notifier.requestAuthorization()
    }
```

- [ ] **Step 4: Remove the free function from Notifying.swift**

In `XcodeCleaner/Services/Notifying.swift`, remove lines 27–34 (the comment block and the free function). The file should end after the `UserNotifier` struct's closing brace (line 25).

- [ ] **Step 5: Update XcodeCleanerApp.swift**

In `XcodeCleaner/App/XcodeCleanerApp.swift`:

Line 7:
```swift
// old
@State private var settings: SettingsModel
// new
@State private var settings: SettingsViewModel
```

Line 14:
```swift
// old
let settings = SettingsModel()
// new
let settings = SettingsViewModel()
```

Line 22:
```swift
// old
Task { await requestSchedulingAuthorizationIfNeeded(settings: settings, notifier: notifier) }
// new
Task { await settings.requestSchedulingAuthorizationIfNeeded(notifier: notifier) }
```

- [ ] **Step 6: Update SettingsView.swift**

In `XcodeCleaner/Views/SettingsView.swift`, replace all `SettingsModel` with `SettingsViewModel` (4 occurrences at lines 5, 8, 26, 70):

```swift
// old
@Bindable var settings: SettingsModel
init(vm: CleanerViewModel, settings: SettingsModel, notifier: Notifying) {
@Bindable var settings: SettingsModel  // GeneralTab line 26
@Bindable var settings: SettingsModel  // ScheduleTab line 70
// new
@Bindable var settings: SettingsViewModel
init(vm: CleanerViewModel, settings: SettingsViewModel, notifier: Notifying) {
@Bindable var settings: SettingsViewModel  // GeneralTab
@Bindable var settings: SettingsViewModel  // ScheduleTab
```

- [ ] **Step 7: Update Scheduler.swift**

In `XcodeCleaner/ViewModels/Scheduler.swift`, two replacements:

Line 7:
```swift
// old
private let settings: SettingsModel
// new
private let settings: SettingsViewModel
```

Line 16:
```swift
// old
init(vm: CleanerViewModel, settings: SettingsModel,
// new
init(vm: CleanerViewModel, settings: SettingsViewModel,
```

- [ ] **Step 8: Update SettingsModelTests.swift**

In `XcodeCleanerTests/SettingsModelTests.swift`, replace every `SettingsModel` with `SettingsViewModel` (10 occurrences: class declaration line 5, and construction sites at lines 14, 25, 28, 34, 40, 53, 54, 62, 69).

> **Note:** Do NOT rename the test class `SettingsModelTests` or the file yet — that happens in Task 12.

- [ ] **Step 9: Update NotifyingTests.swift**

In `XcodeCleanerTests/NotifyingTests.swift`:

Line 12:
```swift
// old
let settings = SettingsModel(userDefaults: makeSuite())
// new
let settings = SettingsViewModel(userDefaults: makeSuite())
```

Line 16:
```swift
// old
await requestSchedulingAuthorizationIfNeeded(settings: settings, notifier: notifier)
// new
await settings.requestSchedulingAuthorizationIfNeeded(notifier: notifier)
```

Line 20:
```swift
// old
await requestSchedulingAuthorizationIfNeeded(settings: settings, notifier: notifier)
// new
await settings.requestSchedulingAuthorizationIfNeeded(notifier: notifier)
```

> **Note:** `NotifyingTests.swift` will be deleted in Task 13 and this test moved to `SettingsViewModelTests.swift`.

- [ ] **Step 10: Update SchedulerTests.swift**

In `XcodeCleanerTests/SchedulerTests.swift`, replace every `SettingsModel` with `SettingsViewModel` (7 occurrences at lines 32, 45, 61, 79, 100, 118, 135).

- [ ] **Step 11: Build + test**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`

- [ ] **Step 12: Commit**

```bash
git add XcodeCleaner/ViewModels/SettingsViewModel.swift XcodeCleaner/Services/Notifying.swift XcodeCleaner/App/XcodeCleanerApp.swift XcodeCleaner/Views/SettingsView.swift XcodeCleaner/ViewModels/Scheduler.swift XcodeCleanerTests/SettingsModelTests.swift XcodeCleanerTests/NotifyingTests.swift XcodeCleanerTests/SchedulerTests.swift
git commit -m "refactor: rename SettingsModel to SettingsViewModel; absorb auth-request method"
```

---

## Task 7: Rename Scheduler to SchedulerViewModel (Layer 3b — ViewModels)

**Files:**
- Rename: `XcodeCleaner/ViewModels/Scheduler.swift` → `SchedulerViewModel.swift`
- Modify: `XcodeCleaner/App/XcodeCleanerApp.swift:8,19`
- Modify: `XcodeCleanerTests/SchedulerTests.swift` (all `Scheduler(` → `SchedulerViewModel(`)

- [ ] **Step 1: Rename the file**

```bash
git mv XcodeCleaner/ViewModels/Scheduler.swift XcodeCleaner/ViewModels/SchedulerViewModel.swift
```

- [ ] **Step 2: Rename the class in SchedulerViewModel.swift**

In `XcodeCleaner/ViewModels/SchedulerViewModel.swift`, line 5:

```swift
// old
final class Scheduler {
// new
final class SchedulerViewModel {
```

- [ ] **Step 3: Update XcodeCleanerApp.swift**

In `XcodeCleaner/App/XcodeCleanerApp.swift`:

Line 8:
```swift
// old
private let scheduler: Scheduler
// new
private let scheduler: SchedulerViewModel
```

Line 19:
```swift
// old
scheduler = Scheduler(vm: vm, settings: settings, notifier: notifier)
// new
scheduler = SchedulerViewModel(vm: vm, settings: settings, notifier: notifier)
```

> **Note:** The init parameter label `vm:` is NOT renamed (see spec Out of scope). The argument is still `vm` at this point — it becomes `cleaner` in Task 8.

- [ ] **Step 4: Update SchedulerTests.swift**

In `XcodeCleanerTests/SchedulerTests.swift`, replace every `Scheduler(vm:` with `SchedulerViewModel(vm:` (7 occurrences at lines 38, 53, 69, 87, 107, 125, 147).

> **Note:** Do NOT rename the test class `SchedulerTests` or the file yet — that happens in Task 12.

- [ ] **Step 5: Build + test**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add XcodeCleaner/ViewModels/SchedulerViewModel.swift XcodeCleaner/App/XcodeCleanerApp.swift XcodeCleanerTests/SchedulerTests.swift
git commit -m "refactor: rename Scheduler to SchedulerViewModel"
```

---

## Task 8: Rename vm property to cleaner in App and Views (Layer 4 — Views/App)

**Files:**
- Modify: `XcodeCleaner/App/XcodeCleanerApp.swift:6,13,16,19,27,30,37`
- Modify: `XcodeCleaner/Views/MenuBarView.swift:4,12,16,20,30,31,32,39,40,41,45,48,66`
- Modify: `XcodeCleaner/Views/SettingsView.swift:4,8,9,18,69,123`

- [ ] **Step 1: Rename vm in XcodeCleanerApp.swift**

In `XcodeCleaner/App/XcodeCleanerApp.swift`, rename the property, the local, the backing assignment, and all reads:

Line 6:
```swift
// old
@State private var vm: CleanerViewModel
// new
@State private var cleaner: CleanerViewModel
```

Line 13:
```swift
// old
let vm = CleanerViewModel()
// new
let cleaner = CleanerViewModel()
```

Line 16:
```swift
// old
_vm = State(initialValue: vm)
// new
_cleaner = State(initialValue: cleaner)
```

Line 19:
```swift
// old
scheduler = SchedulerViewModel(vm: vm, settings: settings, notifier: notifier)
// new
scheduler = SchedulerViewModel(vm: cleaner, settings: settings, notifier: notifier)
```

Line 27:
```swift
// old
MenuBarView(vm: vm)
// new
MenuBarView(cleaner: cleaner)
```

Line 30:
```swift
// old
.symbolEffect(.variableColor.iterative, isActive: vm.isScheduledCleaning)
// new
.symbolEffect(.variableColor.iterative, isActive: cleaner.isScheduledCleaning)
```

Line 37:
```swift
// old
SettingsView(vm: vm, settings: settings, notifier: notifier)
// new
SettingsView(cleaner: cleaner, settings: settings, notifier: notifier)
```

- [ ] **Step 2: Rename vm in MenuBarView.swift**

In `XcodeCleaner/Views/MenuBarView.swift`, rename the property and all reads (13 occurrences):

Line 4:
```swift
// old
let vm: CleanerViewModel
// new
let cleaner: CleanerViewModel
```

Line 12:
```swift
// old
Button { vm.scanAll() } label: { Image(systemName: "arrow.clockwise") }
// new
Button { cleaner.scanAll() } label: { Image(systemName: "arrow.clockwise") }
```

Line 16:
```swift
// old
Text("Reclaimable: \(vm.totalText)")
// new
Text("Reclaimable: \(cleaner.totalText)")
```

Line 20:
```swift
// old
if let status = vm.statusText {
// new
if let status = cleaner.statusText {
```

Lines 30–32:
```swift
// old
ForEach(vm.targets) { target in
    TargetRow(target: target) { vm.clean(target) }
        .disabled(vm.isScheduledCleaning)
// new
ForEach(cleaner.targets) { target in
    TargetRow(target: target) { cleaner.clean(target) }
        .disabled(cleaner.isScheduledCleaning)
```

Lines 39–48:
```swift
// old
if vm.isCleaningAll {
    ProgressView(value: Double(vm.cleanAllCompleted),
                 total: Double(vm.cleanAllTotal))
        .progressViewStyle(.linear)
        .frame(width: 72)
} else {
    Button("Clean") { vm.cleanAll() }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(vm.isScheduledCleaning)
}
// new
if cleaner.isCleaningAll {
    ProgressView(value: Double(cleaner.cleanAllCompleted),
                 total: Double(cleaner.cleanAllTotal))
        .progressViewStyle(.linear)
        .frame(width: 72)
} else {
    Button("Clean") { cleaner.cleanAll() }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(cleaner.isScheduledCleaning)
}
```

Line 66:
```swift
// old
.onAppear { vm.scanAll() }
// new
.onAppear { cleaner.scanAll() }
```

- [ ] **Step 3: Rename vm in SettingsView.swift**

In `XcodeCleaner/Views/SettingsView.swift`, rename the property, the init parameter, the assignment, and all reads:

Line 4:
```swift
// old
let vm: CleanerViewModel
// new
let cleaner: CleanerViewModel
```

Line 8:
```swift
// old
init(vm: CleanerViewModel, settings: SettingsViewModel, notifier: Notifying) {
// new
init(cleaner: CleanerViewModel, settings: SettingsViewModel, notifier: Notifying) {
```

Line 9:
```swift
// old
self.vm = vm
// new
self.cleaner = cleaner
```

Line 18:
```swift
// old
ScheduleTab(vm: vm, settings: settings, notifier: notifier)
// new
ScheduleTab(cleaner: cleaner, settings: settings, notifier: notifier)
```

Line 69 (nested `ScheduleTab` struct):
```swift
// old
let vm: CleanerViewModel
// new
let cleaner: CleanerViewModel
```

Line 123 (inside `ScheduleTab.body`):
```swift
// old
ForEach(vm.targets) { target in
// new
ForEach(cleaner.targets) { target in
```

- [ ] **Step 4: Build + test**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add XcodeCleaner/App/XcodeCleanerApp.swift XcodeCleaner/Views/MenuBarView.swift XcodeCleaner/Views/SettingsView.swift
git commit -m "refactor: rename vm property to cleaner in App and Views"
```

---

## Task 9: Rename test files and classes to match production renames (Layer 5a — Tests)

**Files:**
- Rename: `XcodeCleanerTests/ShellTests.swift` → `CommandRunnerTests.swift` + rename class
- Rename: `XcodeCleanerTests/SchedulingTests.swift` → `ScheduleMathTests.swift` + rename class
- Rename: `XcodeCleanerTests/SchedulerTests.swift` → `SchedulerViewModelTests.swift` + rename class
- Rename: `XcodeCleanerTests/SettingsModelTests.swift` → `SettingsViewModelTests.swift` + rename class

> **Context:** The in-file call-site edits for these files were already done in Tasks 3, 5, 6, and 7. This task only renames the files and the test class declarations.

- [ ] **Step 1: Rename ShellTests.swift → CommandRunnerTests.swift**

```bash
git mv XcodeCleanerTests/ShellTests.swift XcodeCleanerTests/CommandRunnerTests.swift
```

In `XcodeCleanerTests/CommandRunnerTests.swift`, line 4:

```swift
// old
final class ShellTests: XCTestCase {
// new
final class CommandRunnerTests: XCTestCase {
```

- [ ] **Step 2: Rename SchedulingTests.swift → ScheduleMathTests.swift**

```bash
git mv XcodeCleanerTests/SchedulingTests.swift XcodeCleanerTests/ScheduleMathTests.swift
```

In `XcodeCleanerTests/ScheduleMathTests.swift`, line 4:

```swift
// old
final class SchedulingTests: XCTestCase {
// new
final class ScheduleMathTests: XCTestCase {
```

- [ ] **Step 3: Rename SchedulerTests.swift → SchedulerViewModelTests.swift**

```bash
git mv XcodeCleanerTests/SchedulerTests.swift XcodeCleanerTests/SchedulerViewModelTests.swift
```

In `XcodeCleanerTests/SchedulerViewModelTests.swift`, line 5:

```swift
// old
final class SchedulerTests: XCTestCase {
// new
final class SchedulerViewModelTests: XCTestCase {
```

- [ ] **Step 4: Rename SettingsModelTests.swift → SettingsViewModelTests.swift**

```bash
git mv XcodeCleanerTests/SettingsModelTests.swift XcodeCleanerTests/SettingsViewModelTests.swift
```

In `XcodeCleanerTests/SettingsViewModelTests.swift`, line 5:

```swift
// old
final class SettingsModelTests: XCTestCase {
// new
final class SettingsViewModelTests: XCTestCase {
```

- [ ] **Step 5: Build + test**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add XcodeCleanerTests/CommandRunnerTests.swift XcodeCleanerTests/ScheduleMathTests.swift XcodeCleanerTests/SchedulerViewModelTests.swift XcodeCleanerTests/SettingsViewModelTests.swift
git commit -m "refactor: rename test files and classes to match production renames"
```

---

## Task 10: Move auth-request test into SettingsViewModelTests and delete NotifyingTests (Layer 5b — Tests)

**Files:**
- Modify: `XcodeCleanerTests/SettingsViewModelTests.swift` (add the test)
- Delete: `XcodeCleanerTests/NotifyingTests.swift`

> **Context:** The test body was already updated in Task 6 (Step 9) to call `settings.requestSchedulingAuthorizationIfNeeded(notifier:)`. This task moves it to its permanent home and deletes the source file.

- [ ] **Step 1: Read the current test from NotifyingTests.swift**

Read `XcodeCleanerTests/NotifyingTests.swift` to get the exact current test body. After Task 6, it should look like:

```swift
import XCTest
@testable import XcodeCleaner

@MainActor
final class NotifyingTests: XCTestCase {
    private func makeSuite() -> UserDefaults {
        let name = "xclean.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    func testRequestsAuthOnlyWhenSchedulingEnabled() async {
        let settings = SettingsViewModel(userDefaults: makeSuite())
        let notifier = FakeNotifier()

        settings.schedulingEnabled = false
        await settings.requestSchedulingAuthorizationIfNeeded(notifier: notifier)
        XCTAssertEqual(notifier.authorizationRequests, 0)

        settings.schedulingEnabled = true
        await settings.requestSchedulingAuthorizationIfNeeded(notifier: notifier)
        XCTAssertEqual(notifier.authorizationRequests, 1)
    }
}
```

- [ ] **Step 2: Add the test to SettingsViewModelTests.swift**

In `XcodeCleanerTests/SettingsViewModelTests.swift`, add the `makeSuite()` helper (if not already present) and the test method. The file already has a `makeSuite()` helper — check for it and add the test at the end of the class:

```swift
    func testRequestsAuthOnlyWhenSchedulingEnabled() async {
        let settings = SettingsViewModel(userDefaults: makeSuite())
        let notifier = FakeNotifier()

        settings.schedulingEnabled = false
        await settings.requestSchedulingAuthorizationIfNeeded(notifier: notifier)
        XCTAssertEqual(notifier.authorizationRequests, 0)

        settings.schedulingEnabled = true
        await settings.requestSchedulingAuthorizationIfNeeded(notifier: notifier)
        XCTAssertEqual(notifier.authorizationRequests, 1)
    }
```

> **Note:** `SettingsViewModelTests.swift` already has `@MainActor` on the class and a `makeSuite()` helper (from the original `SettingsModelTests`). The test uses `FakeNotifier` from `XcodeCleanerTests/Fakes/FakeNotifier.swift` — already available.

- [ ] **Step 3: Delete NotifyingTests.swift**

```bash
git rm XcodeCleanerTests/NotifyingTests.swift
```

- [ ] **Step 4: Build + test**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **` — verify `testRequestsAuthOnlyWhenSchedulingEnabled` runs under `SettingsViewModelTests` (not `NotifyingTests`).

- [ ] **Step 5: Commit**

```bash
git add XcodeCleanerTests/SettingsViewModelTests.swift XcodeCleanerTests/NotifyingTests.swift
git commit -m "refactor: move auth-request test into SettingsViewModelTests; delete NotifyingTests"
```

---

## Task 11: Split SimctlParsingTests and create CleanupTargetTests (Layer 5c — Tests)

**Files:**
- Create: `XcodeCleanerTests/CleanupTargetTests.swift`
- Modify: `XcodeCleanerTests/SimctlParsingTests.swift` (remove sizeText tests + placeholder)

> **Context:** After Task 1, `SimctlParsingTests.swift` contains: `testPlaceholder`, `testSizeTextFormatsScannedBytes`, `testSizeTextIdleAndScanning`, `testUnusedRuntimeBytesExcludesRecentlyUsed`, `testUnavailableDeviceUDIDs`. The first three are removed/split here; the last two stay.

- [ ] **Step 1: Create CleanupTargetTests.swift**

Create `XcodeCleanerTests/CleanupTargetTests.swift`:

```swift
import XCTest
@testable import XcodeCleaner

final class CleanupTargetTests: XCTestCase {
    func testSizeTextFormatsScannedBytes() {
        let t = CleanupTarget(name: "X", kind: .unavailableSimulators)
        t.state = .scanned(bytes: 1_500_000_000)
        XCTAssertEqual(t.sizeBytes, 1_500_000_000)
        XCTAssertTrue(t.sizeText.contains("GB"))
    }

    func testSizeTextIdleAndScanning() {
        let t = CleanupTarget(name: "X", kind: .unavailableSimulators)
        XCTAssertEqual(t.sizeText, "—")
        t.state = .scanning
        XCTAssertEqual(t.sizeText, "scanning…")
    }
}
```

- [ ] **Step 2: Remove moved tests and placeholder from SimctlParsingTests.swift**

In `XcodeCleanerTests/SimctlParsingTests.swift`, remove `testPlaceholder`, `testSizeTextFormatsScannedBytes`, and `testSizeTextIdleAndScanning`. The file should retain only the two `SimctlParsing` tests:

```swift
import XCTest
@testable import XcodeCleaner

final class SimctlParsingTests: XCTestCase {
    func testUnusedRuntimeBytesExcludesRecentlyUsed() throws {
        let json = """
        {
          "A": { "sizeBytes": 8000000000, "lastUsedAt": "2026-06-20T12:00:00Z" },
          "B": { "sizeBytes": 7000000000, "lastUsedAt": "2026-01-01T12:00:00Z" },
          "C": { "sizeBytes": 1000000000 }
        }
        """.data(using: .utf8)!
        let now = ISO8601DateFormatter().date(from: "2026-06-20T13:00:00Z")!
        // 30-day cutoff: A is recent (keep); B is old (delete); C has no date (delete)
        let bytes = try SimctlParsing.unusedRuntimeBytes(json: json, days: 30, now: now)
        XCTAssertEqual(bytes, 8_000_000_000)
    }

    func testUnavailableDeviceUDIDs() throws {
        let json = """
        { "devices": {
          "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
            { "udid": "AAA", "isAvailable": true },
            { "udid": "BBB", "isAvailable": false }
          ],
          "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
            { "udid": "CCC", "availabilityError": "runtime profile not found" }
          ]
        } }
        """.data(using: .utf8)!
        let udids = try SimctlParsing.unavailableDeviceUDIDs(json: json).sorted()
        XCTAssertEqual(udids, ["BBB", "CCC"])
    }
}
```

- [ ] **Step 3: Build + test**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **` — verify `CleanupTargetTests` runs with 2 tests and `SimctlParsingTests` runs with 2 tests (down from 5).

- [ ] **Step 4: Commit**

```bash
git add XcodeCleanerTests/CleanupTargetTests.swift XcodeCleanerTests/SimctlParsingTests.swift
git commit -m "refactor: split SimctlParsingTests; add CleanupTargetTests; delete placeholder"
```

---

## Final verification

After all 11 tasks are complete, run a full build + test + lint pass:

- [ ] **Full build**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Full test suite**

```bash
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **` — all tests pass.

- [ ] **Lint (if installed)**

```bash
swiftformat . --exclude .build
swiftlint
```

Expected: no errors.

- [ ] **Grep for leftover old names (should be zero matches)**

```bash
rg -t swift 'ScanError|FileManagerAvailability|struct Shell\b|enum Scheduling\b|class SettingsModel\b|class Scheduler\b|requestSchedulingAuthorizationIfNeeded\(settings:' .
```

Expected: no output (all old names are gone).

- [ ] **Grep for leftover `vm` in App/Views (should be zero matches outside SchedulerViewModel's init parameter)**

```bash
rg -t swift '\bvm\b' XcodeCleaner/App XcodeCleaner/Views
```

Expected: no output (the `vm:` parameter label on `SchedulerViewModel.init` is in `ViewModels/`, not `App/` or `Views/`).
