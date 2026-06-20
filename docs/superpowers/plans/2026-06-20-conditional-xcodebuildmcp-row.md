# Conditional XcodeBuildMCP Row Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the "XcodeBuildMCP workspaces" row in the menu appear only when `~/Library/Developer/XcodeBuildMCP/workspaces` exists, instead of always. Other 5 rows unchanged.

**Architecture:** Introduce an `AvailabilityChecking` protocol with a `FileManagerAvailability` concrete impl and a `FakeAvailability` test fake, mirroring the existing `CommandRunning`/`DiskScanning`/`Cleaning` pattern. `CleanerViewModel` gains a fourth injected dependency, `availability`, and conditionally prepends the XcodeBuildMCP row based on it. New behavior is covered by two new tests using the fake, so they run on any host.

**Tech Stack:** Swift 6, SwiftUI, macOS 14, Xcode file-system-synchronized groups, XCTest.

## Global Constraints

- Swift 6.0, macOS 14.0. App Sandbox disabled. Behavior-preserving for the other 5 rows.
- Synchronized groups: `XcodeCleaner/Services/` and `XcodeCleanerTests/Fakes/` auto-include new `.swift` files — NO pbxproj edit needed.
- Build: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6` → `** BUILD SUCCEEDED **`.
- Test: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10` → `** TEST SUCCEEDED **`.
- Parse noisy xcodebuild output by grepping for `BUILD SUCCEEDED`, `TEST SUCCEEDED`, `error:`.
- Spec: `docs/superpowers/specs/2026-06-20-conditional-xcodebuildmcp-row-design.md`.
- Starting state: 15 tests green on `main` (commit `dfb97db` + spec commit `9b05f21`).

---

## File Structure (target)

```
XcodeCleaner/
  Services/   AvailabilityChecking.swift        (new)
  ViewModels/ CleanerViewModel.swift            (modified — add availability dep + conditional row)
XcodeCleanerTests/
  Fakes/ FakeAvailability.swift                 (new)
  CleanerViewModelTests.swift                   (modified — 4 existing tests pass FakeAvailability(true); +2 new tests)
```

No `pbxproj` edits (both new files live inside synchronized groups).

---

### Task 1: `AvailabilityChecking` protocol + `FileManagerAvailability` impl

**Files:**
- Create: `XcodeCleaner/Services/AvailabilityChecking.swift`

**Interfaces:**
- Produces: `protocol AvailabilityChecking: Sendable { func exists(_ path: String) -> Bool }` with `struct FileManagerAvailability: AvailabilityChecking`.

- [ ] **Step 1: Create `Services/AvailabilityChecking.swift`**

```swift
import Foundation

protocol AvailabilityChecking: Sendable {
    func exists(_ path: String) -> Bool
}

struct FileManagerAvailability: AvailabilityChecking {
    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`. (No usages yet, but the file must compile standalone.)

- [ ] **Step 3: Test**

Run the test command. Expected: `** TEST SUCCEEDED **` (still 15 tests; no behavior change yet).

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "refactor: add AvailabilityChecking protocol and FileManagerAvailability"
```

---

### Task 2: `FakeAvailability` test fake

**Files:**
- Create: `XcodeCleanerTests/Fakes/FakeAvailability.swift`

**Interfaces:**
- Produces: `final class FakeAvailability: AvailabilityChecking, @unchecked Sendable` with `init(existsResult: Bool)` and a stored `existsResult: Bool`.

- [ ] **Step 1: Create `Fakes/FakeAvailability.swift`**

```swift
import Foundation
@testable import XcodeCleaner

final class FakeAvailability: AvailabilityChecking, @unchecked Sendable {
    let existsResult: Bool

    init(existsResult: Bool) {
        self.existsResult = existsResult
    }

    func exists(_ path: String) -> Bool {
        existsResult
    }
}
```

(Stateless after init — a single `let Bool` — so no locking is required; `@unchecked Sendable` is correct because the type is effectively immutable.)

- [ ] **Step 2: Build + Test** — Expected `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **` (still 15 tests; no usages yet, fake just has to compile).

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "test: add FakeAvailability"
```

---

### Task 3: Wire `availability` into `CleanerViewModel`; conditionally prepend XcodeBuildMCP row

**Files:**
- Modify: `XcodeCleaner/ViewModels/CleanerViewModel.swift`

**Interfaces:**
- Consumes: `AvailabilityChecking`, `FileManagerAvailability`.
- Produces: `CleanerViewModel.init` gains a fourth parameter `availability: AvailabilityChecking = FileManagerAvailability()`; `targets` is now built dynamically — the XcodeBuildMCP row is included iff `availability.exists(expandedPath)` returns true. Other 5 rows always appended.

- [ ] **Step 1: Replace `ViewModels/CleanerViewModel.swift`** with the new version. The full file (only the `init` and the new stored property change; `scanAll`, `scan`, `clean`, `totalText` are byte-identical to the current file):

```swift
import Foundation

@MainActor
@Observable
final class CleanerViewModel {
    let targets: [CleanupTarget]
    private let scanner: DiskScanning
    private let cleaner: Cleaning
    private let availability: AvailabilityChecking

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

    func scanAll() {
        for t in targets { scan(t) }
    }

    func scan(_ target: CleanupTarget) {
        target.state = .scanning
        Task {
            let result = await scanner.size(of: target)
            switch result {
            case .success(let bytes): target.state = .scanned(bytes)
            case .failure(let err): target.state = .error(err.localizedDescription)
            }
        }
    }

    func clean(_ target: CleanupTarget) {
        target.state = .cleaning
        Task {
            let result = await cleaner.clean(target)
            switch result {
            case .success:
                let rescan = await scanner.size(of: target)
                switch rescan {
                case .success(let bytes): target.state = .cleaned(bytes)
                case .failure(let err): target.state = .error(err.localizedDescription)
                }
            case .failure(let err):
                target.state = .error(err.localizedDescription)
            }
        }
    }

    var totalText: String {
        let total = targets.compactMap(\.sizeBytes).reduce(0, +)
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
```

- [ ] **Step 2: Build** — Expected `** BUILD SUCCEEDED **`. (Tests will still pass because the default `FileManagerAvailability()` on the dev machine returns true for the existing `~/Library/Developer/XcodeBuildMCP/workspaces` dir, so `targets[0]` is still XcodeBuildMCP — but the 4 existing ViewModel tests don't assert names, so they're robust either way.)

- [ ] **Step 3: Test** — Expected `** TEST SUCCEEDED **` (still 15 tests).

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: show XcodeBuildMCP row only when workspaces dir exists"
```

---

### Task 4: Update existing 4 ViewModel tests to pass `FakeAvailability(existsResult: true)`; add 2 new tests for the conditional row

**Files:**
- Modify: `XcodeCleanerTests/CleanerViewModelTests.swift`

**Interfaces:**
- Consumes: `FakeAvailability`, `CleanerViewModel`, `CleanupTarget`.
- Produces: 4 existing tests construct the ViewModel with an explicit `availability: FakeAvailability(existsResult: true)` so `targets[0]` is deterministically "XcodeBuildMCP workspaces" regardless of host; 2 new tests (`testXcodeBuildMCPRowPresentWhenInstalled`, `testXcodeBuildMCPRowAbsentWhenNotInstalled`) assert the row's presence/absence driven by the fake.

- [ ] **Step 1: Replace `CleanerViewModelTests.swift`** with the full file below. The 4 existing test bodies are unchanged except for the `CleanerViewModel(...)` constructor call gaining a third argument `availability: FakeAvailability(existsResult: true)`; two new tests are appended inside the same `@MainActor final class CleanerViewModelTests`:

```swift
import XCTest
@testable import XcodeCleaner

@MainActor
final class CleanerViewModelTests: XCTestCase {
    /// Polls until `cond` is true or the timeout elapses (ViewModel mutates state from an async Task).
    private func waitUntil(timeout: TimeInterval = 2.0, _ cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testScanSetsScannedBytes() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(123)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true))
        let target = vm.targets[0]
        vm.scan(target)
        await waitUntil { if case .scanned = target.state { return true }; return false }
        XCTAssertEqual(target.sizeBytes, 123)
    }

    func testScanFailureSetsError() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .failure(ScanError.process("x"))),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true))
        let target = vm.targets[0]
        vm.scan(target)
        await waitUntil { if case .error = target.state { return true }; return false }
        if case .error = target.state {} else { XCTFail("expected .error state") }
    }

    func testCleanSetsCleanedBytes() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true))
        let target = vm.targets[0]
        vm.clean(target)
        await waitUntil { if case .cleaned = target.state { return true }; return false }
        XCTAssertEqual(target.sizeBytes, 0)
    }

    func testCleanFailureSetsError() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .failure(ScanError.process("y"))),
                                  availability: FakeAvailability(existsResult: true))
        let target = vm.targets[0]
        vm.clean(target)
        await waitUntil { if case .error = target.state { return true }; return false }
        if case .error = target.state {} else { XCTFail("expected .error state") }
    }

    func testXcodeBuildMCPRowPresentWhenInstalled() {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true))
        XCTAssertEqual(vm.targets.first?.name, "XcodeBuildMCP workspaces")
        XCTAssertTrue(vm.targets.contains { $0.name == "XcodeBuildMCP workspaces" })
    }

    func testXcodeBuildMCPRowAbsentWhenNotInstalled() {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: false))
        XCTAssertFalse(vm.targets.contains { $0.name == "XcodeBuildMCP workspaces" })
        XCTAssertEqual(vm.targets.first?.name, "Xcode DerivedData")
    }
}
```

- [ ] **Step 2: Build + Test** — Expected `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`. Confirm the 2 new tests ran: grep the test output for `testXcodeBuildMCPRowPresentWhenInstalled` and `testXcodeBuildMCPRowAbsentWhenNotInstalled`. Total should be 17 tests (15 existing + 2 new).

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "test: pin ViewModel tests to FakeAvailability; cover conditional XcodeBuildMCP row"
```

---

## Self-Review Notes

- **Spec coverage:** `AvailabilityChecking` protocol + `FileManagerAvailability` (Task 1); `FakeAvailability` (Task 2); `CleanerViewModel` conditional prepend using `availability.exists` on the expanded path (Task 3); existing 4 tests pinned to `FakeAvailability(true)`, 2 new tests for presence/absence (Task 4). Every section of the spec maps to a task.
- **Behavior preservation:** the other 5 rows are appended unconditionally in the same order as before. `scanAll`/`scan`/`clean`/`totalText` are byte-identical. Production default `FileManagerAvailability()` returns true on any machine that has the workspaces dir (the only behavior change is on machines that don't — exactly the intended fix).
- **Placeholder scan:** no TBDs; full target code given for every file; exact commands with expected output.
- **Type consistency:** `AvailabilityChecking.exists(_ path: String) -> Bool` matches `FileManagerAvailability.exists`, `FakeAvailability.exists`, and the `availability.exists(xbmcpPath)` call in `CleanerViewModel.init`. `FakeAvailability(existsResult: Bool)` parameter name matches all 6 test call sites. `CleanerViewModel.init`'s 4th parameter `availability: AvailabilityChecking = FileManagerAvailability()` matches the 3-arg calls in the 4 existing tests + 2 new tests (all passing `availability: FakeAvailability(...)`).
