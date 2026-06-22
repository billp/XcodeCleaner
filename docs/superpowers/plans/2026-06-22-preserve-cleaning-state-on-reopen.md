# Preserve In-Flight State on Menu Reopen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the menu's auto-rescan from clobbering a row that is mid-clean (or mid-scan) when the popover is reopened.

**Architecture:** Add a guard at the top of `CleanerViewModel.scan(_:)` that returns early when the target is already `.scanning` or `.cleaning`. Both `scanAll()` and the manual refresh button route through `scan(_:)`, so the single guard covers every rescan path.

**Tech Stack:** Swift, SwiftUI, XCTest. macOS menu-bar app (`MenuBarExtra`).

## Global Constraints

- `@MainActor`-isolated view model; all `target.state` writes happen on the main actor.
- Tests use the existing fakes: `FakeScanner`, `FakeCleaner`, `FakeAvailability`, `CleanGate`.
- Existing test style: poll via the `waitUntil` helper for async `Task`-driven state changes.

---

### Task 1: Guard `scan(_:)` against busy targets

**Files:**
- Modify: `XcodeCleaner/ViewModels/CleanerViewModel.swift:43-52`
- Test: `XcodeCleanerTests/CleanerViewModelTests.swift`

**Interfaces:**
- Consumes: `CleanerViewModel.scan(_ target: CleanupTarget)`, `CleanerViewModel.scanAll()`, `CleanupTarget.state: TargetState` (settable), `TargetState` cases `.idle/.scanning/.cleaning/.scanned/.cleaned/.error`.
- Produces: no signature changes; `scan(_:)` becomes a no-op when `target.state` is `.scanning` or `.cleaning`.

- [ ] **Step 1: Write the failing test**

Add to `XcodeCleanerTests/CleanerViewModelTests.swift` (inside the class):

```swift
func testScanAllPreservesCleaningTarget() async {
    let vm = CleanerViewModel(scanner: FakeScanner(result: .success(123)),
                              cleaner: FakeCleaner(result: .success(())),
                              availability: FakeAvailability(existsResult: false))
    let cleaning = vm.targets[0]
    let idle = vm.targets[1]
    cleaning.state = .cleaning           // simulate an in-flight clean

    vm.scanAll()                         // mimics the onAppear auto-rescan

    // The busy row keeps its cleaning state…
    XCTAssertEqual(cleaning.state, .cleaning)
    // …while an idle row still rescans.
    await waitUntil { idle.sizeBytes == 123 }
    XCTAssertEqual(idle.sizeBytes, 123)
    XCTAssertEqual(cleaning.state, .cleaning)
}

func testScanSkipsAlreadyScanningTarget() async {
    let vm = CleanerViewModel(scanner: FakeScanner(result: .success(123)),
                              cleaner: FakeCleaner(result: .success(())),
                              availability: FakeAvailability(existsResult: false))
    let target = vm.targets[0]
    target.state = .scanning

    vm.scan(target)          // should be a no-op, not restart a scan

    // Give any (wrong) scan Task a chance to run, then confirm state unchanged.
    try? await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertEqual(target.state, .scanning)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme XcodeCleaner -destination 'platform=macOS' \
  -only-testing:XcodeCleanerTests/CleanerViewModelTests/testScanAllPreservesCleaningTarget \
  -only-testing:XcodeCleanerTests/CleanerViewModelTests/testScanSkipsAlreadyScanningTarget 2>&1 | tail -25
```
Expected: FAIL — `testScanAllPreservesCleaningTarget` fails because `cleaning.state` becomes `.scanning`/`.scanned` instead of `.cleaning`; `testScanSkipsAlreadyScanningTarget` fails because the state transitions to `.scanned`.

- [ ] **Step 3: Add the guard to `scan(_:)`**

In `XcodeCleaner/ViewModels/CleanerViewModel.swift`, replace the body of `scan(_:)` (currently starting at line 43) so it begins with the guard:

```swift
func scan(_ target: CleanupTarget) {
    switch target.state {
    case .scanning, .cleaning: return   // don't disturb in-flight work
    default: break
    }
    target.state = .scanning
    Task {
        let result = await scanner.size(of: target.kind)
        switch result {
        case .success(let bytes): target.state = .scanned(bytes: bytes)
        case .failure(let err): target.state = .error(message: err.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme XcodeCleaner -destination 'platform=macOS' \
  -only-testing:XcodeCleanerTests/CleanerViewModelTests/testScanAllPreservesCleaningTarget \
  -only-testing:XcodeCleanerTests/CleanerViewModelTests/testScanSkipsAlreadyScanningTarget 2>&1 | tail -25
```
Expected: PASS (`** TEST SUCCEEDED **`).

- [ ] **Step 5: Run the full suite to check for regressions**

Run:
```bash
xcodebuild test -scheme XcodeCleaner -destination 'platform=macOS' 2>&1 | tail -25
```
Expected: PASS. In particular `testCleanAllCleansEveryNonZeroTarget` and the scan tests still pass — those targets start `.idle`, so the new guard does not skip them.

- [ ] **Step 6: Commit**

```bash
git add XcodeCleaner/ViewModels/CleanerViewModel.swift XcodeCleanerTests/CleanerViewModelTests.swift
git commit -m "fix: don't rescan in-flight rows so reopening the menu keeps cleaning state"
```
