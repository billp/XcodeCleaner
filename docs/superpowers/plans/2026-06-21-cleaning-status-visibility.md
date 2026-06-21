# Cleaning-Status Visibility + Notification Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cleaning visible (menu bar icon + prominent dropdown banner for both scheduled and manual cleans) and fix scheduled-clean notifications by requesting authorization on launch when scheduling is enabled.

**Architecture:** Add derived busy state to `CleanerViewModel`; drive the `MenuBarExtra` icon and a `MenuBarView` banner from it; add a testable `requestSchedulingAuthorizationIfNeeded` helper called at launch.

**Tech Stack:** Swift 6, SwiftUI (Observation, `symbolEffect`), UserNotifications, XCTest. macOS 14.

## Global Constraints

- Swift 6.0, macOS 14.0. Follow existing protocol-DI + `OSAllocatedUnfairLock` fake patterns.
- Status copy: scheduled = `"Scheduled clean in progress…"`, manual = `"Cleaning…"`.
- Concurrent manual cleans stay allowed (do not disable non-active rows during a manual clean). Scheduled run keeps disabling all Clean buttons (existing `.disabled(vm.isScheduledCleaning)`).
- Behavior-preserving otherwise. Build + full suite green after each task.
- Build: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner -derivedDataPath /tmp/xccdd build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -3`
- Test: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner -derivedDataPath /tmp/xccdd test CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Executed .* tests|TEST (SUCCEEDED|FAILED)|error:" | tail -4`
- Launch for manual checks (avoid stale-binary trap): `killall XcodeCleaner 2>/dev/null; "/tmp/xccdd/Build/Products/Debug/XcodeCleaner.app/Contents/MacOS/XcodeCleaner" >/dev/null 2>&1 &`

---

## File Structure

```
XcodeCleaner/ViewModels/CleanerViewModel.swift  (modify: isManualCleaning, isBusy, statusText)
XcodeCleaner/Services/Notifying.swift           (modify: add requestSchedulingAuthorizationIfNeeded helper)
XcodeCleaner/App/XcodeCleanerApp.swift          (modify: MenuBarExtra label icon + request auth on launch)
XcodeCleaner/Views/MenuBarView.swift            (modify: prominent status banner)
XcodeCleanerTests/CleanerViewModelTests.swift   (add busy-state tests)
XcodeCleanerTests/NotifyingTests.swift          (new: auth-on-launch helper tests)
```

---

### Task 1: Derived busy state on `CleanerViewModel`

**Files:**
- Modify: `XcodeCleaner/ViewModels/CleanerViewModel.swift`
- Test: `XcodeCleanerTests/CleanerViewModelTests.swift`

**Interfaces:**
- Produces: `var isManualCleaning: Bool`, `var isBusy: Bool`, `var statusText: String?` on `CleanerViewModel`.

- [ ] **Step 1: Write failing test** (append inside `CleanerViewModelTests`)

```swift
func testBusyStateReflectsManualCleaning() {
    let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                              cleaner: FakeCleaner(result: .success(())),
                              availability: FakeAvailability(existsResult: false))
    XCTAssertFalse(vm.isManualCleaning)
    XCTAssertFalse(vm.isBusy)
    XCTAssertNil(vm.statusText)

    vm.targets[0].state = .cleaning
    XCTAssertTrue(vm.isManualCleaning)
    XCTAssertTrue(vm.isBusy)
    XCTAssertEqual(vm.statusText, "Cleaning…")

    vm.targets[0].state = .cleaned(0)
    XCTAssertFalse(vm.isBusy)
    XCTAssertNil(vm.statusText)
}
```

- [ ] **Step 2: Run test → fail** (test command). Expected: FAIL — `isManualCleaning`/`isBusy`/`statusText` undefined.

- [ ] **Step 3: Add the computed properties** to `CleanerViewModel` (place after `totalText`)

```swift
var isManualCleaning: Bool {
    targets.contains { if case .cleaning = $0.state { return true } else { return false } }
}

var isBusy: Bool { isScheduledCleaning || isManualCleaning }

var statusText: String? {
    if isScheduledCleaning { return "Scheduled clean in progress…" }
    if isManualCleaning { return "Cleaning…" }
    return nil
}
```

- [ ] **Step 4: Run test → pass.** Expected `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add derived busy state (isBusy/statusText) to CleanerViewModel"
```

---

### Task 2: Request notification auth on launch when scheduling enabled

**Files:**
- Modify: `XcodeCleaner/Services/Notifying.swift`
- Create: `XcodeCleanerTests/NotifyingTests.swift`

**Interfaces:**
- Consumes: `SettingsModel`, `Notifying`, `FakeNotifier`.
- Produces: `@MainActor func requestSchedulingAuthorizationIfNeeded(settings: SettingsModel, notifier: Notifying) async`.

- [ ] **Step 1: Write failing test** (`XcodeCleanerTests/NotifyingTests.swift`)

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
        let settings = SettingsModel(userDefaults: makeSuite())
        let notifier = FakeNotifier()

        settings.schedulingEnabled = false
        await requestSchedulingAuthorizationIfNeeded(settings: settings, notifier: notifier)
        XCTAssertEqual(notifier.authorizationRequests, 0)

        settings.schedulingEnabled = true
        await requestSchedulingAuthorizationIfNeeded(settings: settings, notifier: notifier)
        XCTAssertEqual(notifier.authorizationRequests, 1)
    }
}
```

- [ ] **Step 2: Run test → fail.** Expected: FAIL — `requestSchedulingAuthorizationIfNeeded` undefined.

- [ ] **Step 3: Add the helper** at the end of `XcodeCleaner/Services/Notifying.swift`

```swift
/// Requests notification authorization at launch when scheduling is already
/// enabled. The Schedule toggle's onChange only fires on a fresh toggle, so a
/// persisted-enabled schedule would otherwise never (re)request authorization.
@MainActor
func requestSchedulingAuthorizationIfNeeded(settings: SettingsModel, notifier: Notifying) async {
    guard settings.schedulingEnabled else { return }
    await notifier.requestAuthorization()
}
```

- [ ] **Step 4: Run test → pass.** Expected `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: requestSchedulingAuthorizationIfNeeded helper"
```

---

### Task 3: Menu bar icon + prominent banner + launch wiring

**Files:**
- Modify: `XcodeCleaner/App/XcodeCleanerApp.swift`
- Modify: `XcodeCleaner/Views/MenuBarView.swift`

**Interfaces:**
- Consumes: `vm.isBusy`, `vm.statusText`, `requestSchedulingAuthorizationIfNeeded`.

- [ ] **Step 1: MenuBarExtra icon + launch auth (`XcodeCleanerApp.swift`).** Replace the `MenuBarExtra("Xcode Cleaner", systemImage: "sparkles") { MenuBarView(vm: vm) } .menuBarExtraStyle(.window)` block with the `label:` form, and request auth on launch in `init()`.

In `init()`, after `scheduler.start()`, add:
```swift
        Task { await requestSchedulingAuthorizationIfNeeded(settings: settings, notifier: notifier) }
```

Change the scene:
```swift
        MenuBarExtra {
            MenuBarView(vm: vm)
        } label: {
            Image(systemName: "sparkles")
                .symbolEffect(.variableColor.iterative, isActive: vm.isBusy)
        }
        .menuBarExtraStyle(.window)
```

- [ ] **Step 2: Prominent banner (`MenuBarView.swift`).** Replace the existing scheduled-only banner block:
```swift
            if vm.isScheduledCleaning {
                Label("Scheduled clean in progress…", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```
with a unified, more prominent banner driven by `statusText`:
```swift
            if let status = vm.statusText {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status).font(.callout).bold()
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
```
(Leave the `ForEach(vm.targets) { … }.disabled(vm.isScheduledCleaning)` rows and everything else unchanged.)

- [ ] **Step 3: Build + full test suite.** Build → `** BUILD SUCCEEDED **`; test → `** TEST SUCCEEDED **` (all prior tests + the 2 new ones).

- [ ] **Step 4: Manual verification.** Launch directly from `/tmp/xccdd` (see Global Constraints). With the dropdown open, click a Clean on a non-empty target (e.g. SwiftPM cache) → the banner shows "Cleaning…" with a spinner and the menu bar `sparkles` icon pulses; both clear when done. Confirm Settings toggling scheduling on still prompts for notification permission.

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: menu bar cleaning indicator, prominent status banner, launch auth request"
```

---

## Self-Review Notes

- **Spec coverage:** busy state (Task 1); auth-on-launch helper + test (Task 2); menu bar icon pulse, prominent banner for both scheduled+manual, launch wiring (Task 3). All covered. The notification root-cause fix is the launch-time auth request (Task 2 + Task 3 Step 1).
- **Placeholder scan:** none — complete code in every step.
- **Type consistency:** `isBusy`/`statusText`/`isManualCleaning` used identically in VM, views; `requestSchedulingAuthorizationIfNeeded(settings:notifier:)` matches between helper, test, and app init; `FakeNotifier.authorizationRequests` matches the existing fake.
- **Note:** scheduled-branch of `statusText` isn't unit-asserted because `isScheduledCleaning` is `private(set)`; it's exercised by the existing `runScheduledClean` flow and verified manually. Manual + idle branches are unit-tested.
