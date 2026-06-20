# Scheduled-Clean Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While a scheduled clean runs, disable manual cleaning (with a banner); persist & show a "Last scheduled clean" timestamp; and post a completion notification reporting reclaimed space and cache count.

**Architecture:** A new `Notifying` service (protocol + `UserNotifier`, with a `FakeNotifier` for tests). `CleanerViewModel` gains an awaitable `runScheduledClean` and an `isScheduledCleaning` flag. `Scheduler` awaits it, records the timestamp on `SettingsModel`, and notifies. Views react to the flag and show the new field.

**Tech Stack:** Swift 6, SwiftUI, Observation, UserNotifications, XCTest. macOS 14.

## Global Constraints

- Swift 6.0, macOS 14.0. Follow the existing protocol-DI + `@unchecked Sendable` fake pattern (lock-guarded via `OSAllocatedUnfairLock`).
- Notification permission requested **when scheduling is enabled** (toggle on).
- Notification body: `"Scheduled clean finished — freed <ByteCountFormatter .file> across <N> cache(s)."` (singular "cache" when N==1).
- During a scheduled run: Clean buttons disabled + banner "Scheduled clean in progress…"; refresh/quit stay live.
- Behavior-preserving elsewhere. Build + full test suite green after every task.
- Build: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner -derivedDataPath /tmp/xccdd build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -3`
- Test: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner -derivedDataPath /tmp/xccdd test CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "Executed .* tests|TEST (SUCCEEDED|FAILED)|error:" | tail -5`
- **Launch for manual checks (avoid the stale-binary trap): always launch the product from `/tmp/xccdd` directly, not via `open` with a globbed DerivedData path:** `killall XcodeCleaner 2>/dev/null; "/tmp/xccdd/Build/Products/Debug/XcodeCleaner.app/Contents/MacOS/XcodeCleaner" >/dev/null 2>&1 &`

---

## File Structure

```
XcodeCleaner/Services/Notifying.swift        (new: protocol + UserNotifier)
XcodeCleaner/ViewModels/SettingsModel.swift  (modify: lastScheduledClean + lastRunText)
XcodeCleaner/ViewModels/CleanerViewModel.swift (modify: isScheduledCleaning, performClean, runScheduledClean; remove cleanTargets)
XcodeCleaner/ViewModels/Scheduler.swift      (modify: notifier injection; tick records + notifies)
XcodeCleaner/Views/MenuBarView.swift         (modify: banner + disable rows)
XcodeCleaner/Views/SettingsView.swift        (modify: last-run row; auth-on-enable; notifier param)
XcodeCleaner/App/XcodeCleanerApp.swift       (modify: create + inject notifier)
XcodeCleanerTests/Fakes/FakeNotifier.swift   (new)
XcodeCleanerTests/Fakes/FakeScanner.swift    (modify: scripted sequence)
XcodeCleanerTests/CleanerViewModelTests.swift (add runScheduledClean test)
XcodeCleanerTests/SchedulerTests.swift       (add notify/last-run test; inject FakeNotifier)
XcodeCleanerTests/SettingsModelTests.swift   (add persistence tests)
```

---

### Task 1: `Notifying` service + `FakeNotifier`

**Files:**
- Create: `XcodeCleaner/Services/Notifying.swift`
- Create: `XcodeCleanerTests/Fakes/FakeNotifier.swift`

**Interfaces:**
- Produces:
  - `protocol Notifying: Sendable { func requestAuthorization() async; func notifyCleanFinished(targetCount: Int, reclaimedBytes: Int64) async }`
  - `struct UserNotifier: Notifying`
  - `final class FakeNotifier: Notifying` with `authorizationRequests: Int` and `finishedCalls: [(count: Int, bytes: Int64)]`.

- [ ] **Step 1: Create `Services/Notifying.swift`**

```swift
import Foundation
import UserNotifications

protocol Notifying: Sendable {
    func requestAuthorization() async
    func notifyCleanFinished(targetCount: Int, reclaimedBytes: Int64) async
}

struct UserNotifier: Notifying {
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    func notifyCleanFinished(targetCount: Int, reclaimedBytes: Int64) async {
        let content = UNMutableNotificationContent()
        content.title = "Xcode Cleaner"
        let size = ByteCountFormatter.string(fromByteCount: reclaimedBytes, countStyle: .file)
        let caches = targetCount == 1 ? "cache" : "caches"
        content.body = "Scheduled clean finished — freed \(size) across \(targetCount) \(caches)."
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 2: Create `XcodeCleanerTests/Fakes/FakeNotifier.swift`**

```swift
import Foundation
import os
@testable import XcodeCleaner

final class FakeNotifier: Notifying, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _authCount = 0
    private var _finished: [(count: Int, bytes: Int64)] = []

    var authorizationRequests: Int { lock.withLock { _authCount } }
    var finishedCalls: [(count: Int, bytes: Int64)] { lock.withLock { _finished } }

    func requestAuthorization() async { lock.withLock { _authCount += 1 } }

    func notifyCleanFinished(targetCount: Int, reclaimedBytes: Int64) async {
        lock.withLock { _finished.append((targetCount, reclaimedBytes)) }
    }
}
```

- [ ] **Step 3: Build** — run the build command. Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add Notifying service and FakeNotifier"
```

---

### Task 2: `SettingsModel.lastScheduledClean` + `lastRunText`

**Files:**
- Modify: `XcodeCleaner/ViewModels/SettingsModel.swift`
- Test: `XcodeCleanerTests/SettingsModelTests.swift`

**Interfaces:**
- Produces: `var lastScheduledClean: Date?` (persisted, observable) and `var lastRunText: String?` (computed).

- [ ] **Step 1: Write failing tests** (append inside the existing `SettingsModelTests` class)

```swift
func testLastScheduledCleanPersistsAcrossInstances() {
    let name = "xclean.test.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    defer { suite.removePersistentDomain(forName: name) }
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    SettingsModel(userDefaults: suite).lastScheduledClean = date
    let reloaded = SettingsModel(userDefaults: suite).lastScheduledClean
    XCTAssertEqual(reloaded?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 1)
}

func testLastRunTextNilWhenNeverRun() {
    let name = "xclean.test.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    defer { suite.removePersistentDomain(forName: name) }
    XCTAssertNil(SettingsModel(userDefaults: suite).lastRunText)
}
```

- [ ] **Step 2: Run tests → fail** with the test command. Expected: FAIL (`lastScheduledClean`/`lastRunText` undefined).

- [ ] **Step 3: Add the properties** to `SettingsModel` (place after `enabledTargetNames`, before `nextRunText`)

```swift
var lastScheduledClean: Date? {
    get {
        access(keyPath: \.lastScheduledClean)
        return defaults.object(forKey: "xclean.lastScheduledClean") as? Date
    }
    set {
        withMutation(keyPath: \.lastScheduledClean) {
            defaults.set(newValue, forKey: "xclean.lastScheduledClean")
        }
    }
}

var lastRunText: String? {
    access(keyPath: \.lastRunText)
    guard let date = lastScheduledClean else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
    return formatter.string(from: date)
}
```

- [ ] **Step 4: Run tests → pass.** Expected `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: persist and format lastScheduledClean in SettingsModel"
```

---

### Task 3: `CleanerViewModel` scheduled-clean + `FakeScanner` sequence

**Files:**
- Modify: `XcodeCleanerTests/Fakes/FakeScanner.swift`
- Modify: `XcodeCleaner/ViewModels/CleanerViewModel.swift`
- Test: `XcodeCleanerTests/CleanerViewModelTests.swift`

**Interfaces:**
- Consumes: `DiskScanning`, `Cleaning`.
- Produces: `CleanerViewModel.isScheduledCleaning: Bool` (observable, private(set)); `func runScheduledClean(named: Set<String>) async -> (count: Int, reclaimed: Int64)`. Removes `cleanTargets(named:)`.
- `FakeScanner` gains `init(results: [Result<Int64, Error>])` returning each in sequence (last repeats).

- [ ] **Step 1: Extend `FakeScanner`** to support a scripted sequence (keep the existing `init(result:)`)

```swift
import Foundation
import os
@testable import XcodeCleaner

final class FakeScanner: DiskScanning, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _results: [Result<Int64, Error>]
    private var _scannedNames: [String] = []

    init(result: Result<Int64, Error>) { self._results = [result] }
    init(results: [Result<Int64, Error>]) { self._results = results }

    var scannedNames: [String] { lock.withLock { _scannedNames } }

    func size(of target: CleanupTarget) async -> Result<Int64, Error> {
        let name = target.name
        return lock.withLock {
            _scannedNames.append(name)
            if _results.count > 1 { return _results.removeFirst() }
            return _results.first ?? .success(0)
        }
    }
}
```

- [ ] **Step 2: Write failing test** (append inside `CleanerViewModelTests`)

```swift
func testRunScheduledCleanReclaimsAndClearsFlag() async {
    let scanner = FakeScanner(results: [.success(1000), .success(0)]) // before, after
    let vm = CleanerViewModel(scanner: scanner,
                              cleaner: FakeCleaner(result: .success(())),
                              availability: FakeAvailability(existsResult: false))
    let name = vm.targets.first!.name
    let result = await vm.runScheduledClean(named: [name])
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.reclaimed, 1000)
    XCTAssertFalse(vm.isScheduledCleaning)
}
```

- [ ] **Step 3: Run test → fail.** Expected: FAIL (`runScheduledClean`/`isScheduledCleaning` undefined).

- [ ] **Step 4: Update `CleanerViewModel`** — add the flag, extract `performClean`, add `runScheduledClean`, and remove `cleanTargets`. Replace the `clean(_:)` method and the old `cleanTargets(named:)` with:

```swift
private(set) var isScheduledCleaning = false

func clean(_ target: CleanupTarget) {
    Task { _ = await performClean(target) }
}

/// Cleans one target, returning bytes reclaimed (before − after).
private func performClean(_ target: CleanupTarget) async -> Int64 {
    var before = target.sizeBytes
    if before == nil, case .success(let b) = await scanner.size(of: target) {
        before = b
    }
    target.state = .cleaning
    let result = await cleaner.clean(target)
    switch result {
    case .success:
        switch await scanner.size(of: target) {
        case .success(let after):
            target.state = .cleaned(after)
            return max(0, (before ?? after) - after)
        case .failure(let err):
            target.state = .error(err.localizedDescription)
            return 0
        }
    case .failure(let err):
        target.state = .error(err.localizedDescription)
        return 0
    }
}

/// Cleans all named targets in sequence; returns count cleaned + total reclaimed.
func runScheduledClean(named names: Set<String>) async -> (count: Int, reclaimed: Int64) {
    isScheduledCleaning = true
    defer { isScheduledCleaning = false }
    var reclaimed: Int64 = 0
    var count = 0
    for target in targets where names.contains(target.name) {
        reclaimed += await performClean(target)
        count += 1
    }
    return (count, reclaimed)
}
```

(The existing `scan(_:)`, `scanAll()`, `totalText` are unchanged. Delete the old `cleanTargets(named:)` method entirely.)

- [ ] **Step 5: Run test → pass.** Expected `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add runScheduledClean and isScheduledCleaning to CleanerViewModel"
```

---

### Task 4: `Scheduler` notify + record last run

**Files:**
- Modify: `XcodeCleaner/ViewModels/Scheduler.swift`
- Test: `XcodeCleanerTests/SchedulerTests.swift`

**Interfaces:**
- Consumes: `CleanerViewModel.runScheduledClean`, `SettingsModel.lastScheduledClean`, `Notifying`, `FakeNotifier`.
- Produces: `Scheduler.init(vm:settings:runner:notifier:)` with `notifier: Notifying = UserNotifier()`.

- [ ] **Step 1: Write failing test** (append inside `SchedulerTests`)

```swift
func testTickRecordsLastCleanAndNotifies() async {
    let settings = SettingsModel(userDefaults: makeSuite())
    settings.schedulingEnabled = true
    settings.enabledTargetNames = ["Xcode DerivedData"]
    let vm = CleanerViewModel(scanner: FakeScanner(results: [.success(1000), .success(0)]),
                              cleaner: FakeCleaner(result: .success(())),
                              availability: FakeAvailability(existsResult: false))
    let notifier = FakeNotifier()
    let scheduler = Scheduler(vm: vm, settings: settings,
                              runner: FakeCommandRunner(status: 0, stdout: Data("bash\n".utf8)),
                              notifier: notifier)
    let fire = makeFireDate()
    await scheduler.tick(now: fire)
    XCTAssertEqual(settings.lastScheduledClean, fire)
    XCTAssertEqual(notifier.finishedCalls.count, 1)
    XCTAssertEqual(notifier.finishedCalls.first?.count, 1)
}
```

- [ ] **Step 2: Run test → fail.** Expected: FAIL (no `notifier:` parameter; `lastScheduledClean` not set by tick).

- [ ] **Step 3: Update `Scheduler`** — add the stored notifier + init param, and rewrite the fire block in `tick(now:)`.

Add the property and init parameter:

```swift
private let notifier: Notifying

init(vm: CleanerViewModel, settings: SettingsModel,
     runner: CommandRunning = Shell(), notifier: Notifying = UserNotifier()) {
    self.vm = vm
    self.settings = settings
    self.runner = runner
    self.notifier = notifier
}
```

Replace the final fire block (currently `vm.cleanTargets(named: settings.enabledTargetNames)` … through the resets) with:

```swift
let result = await vm.runScheduledClean(named: settings.enabledTargetNames)
settings.lastScheduledClean = now
await notifier.notifyCleanFinished(targetCount: result.count, reclaimedBytes: result.reclaimed)
lastFired = now
pendingFire = nil
originalFire = nil
```

- [ ] **Step 4: Inject `FakeNotifier` into the existing fire test** so it doesn't touch the real notification center. In `testTickFiresWhenNoBuildProcessRunning`, change the `Scheduler(...)` construction to pass `notifier: FakeNotifier()` (add the argument; leave the rest of that test unchanged).

- [ ] **Step 5: Run tests → pass.** Expected `** TEST SUCCEEDED **` (all scheduler tests green).

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: scheduler records last run and posts completion notification"
```

---

### Task 5: Views + app wiring (banner, disable, last-run row, auth-on-enable)

**Files:**
- Modify: `XcodeCleaner/Views/MenuBarView.swift`
- Modify: `XcodeCleaner/Views/SettingsView.swift`
- Modify: `XcodeCleaner/App/XcodeCleanerApp.swift`

**Interfaces:**
- Consumes: `vm.isScheduledCleaning`, `settings.lastRunText`, `Notifying`.
- Produces: `SettingsView.init(vm:settings:notifier:)`.

- [ ] **Step 1: MenuBarView — banner + disabled rows.** Replace the targets `ForEach` block and the divider above it with:

```swift
            Divider()
            if vm.isScheduledCleaning {
                Label("Scheduled clean in progress…", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(vm.targets) { target in
                TargetRow(target: target) { vm.clean(target) }
                    .disabled(vm.isScheduledCleaning)
            }
```

Also make the bottom **Settings… / Quit** buttons full width. Replace the existing Settings/Quit button block with:

```swift
            Divider()
            Button("Settings…") {
                openWindow(id: XcodeCleanerApp.settingsWindowID)
                NSApp.activate()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .frame(maxWidth: .infinity, alignment: .leading)
```

(Leave the header, Reclaimable line, and `.onAppear` unchanged.)

- [ ] **Step 2: SettingsView — accept a notifier and add the last-run row + auth-on-enable.**

Change the `SettingsView` declaration/init to take a notifier and pass it to `ScheduleTab`:

```swift
struct SettingsView: View {
    let vm: CleanerViewModel
    @Bindable var settings: SettingsModel
    let notifier: Notifying

    init(vm: CleanerViewModel, settings: SettingsModel, notifier: Notifying) {
        self.vm = vm
        self.settings = settings
        self.notifier = notifier
    }

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ScheduleTab(vm: vm, settings: settings, notifier: notifier)
                .tabItem { Label("Schedule", systemImage: "clock") }
        }
        .frame(width: 480, height: 380)
    }
}
```

In `GeneralTab`, add a last-run row to the "Scheduled cleaning" section (after the `if settings.schedulingEnabled { … } else { … }` block, still inside the `Section`):

```swift
                LabeledContent("Last scheduled clean",
                               value: settings.lastRunText ?? "Never")
```

In `ScheduleTab`, add a stored `let notifier: Notifying`, and attach `.onChange` to the enable toggle:

```swift
private struct ScheduleTab: View {
    let vm: CleanerViewModel
    @Bindable var settings: SettingsModel
    let notifier: Notifying
```

```swift
            Section {
                Toggle("Enable scheduled cleaning", isOn: $settings.schedulingEnabled)
                    .onChange(of: settings.schedulingEnabled) { _, isOn in
                        if isOn { Task { await notifier.requestAuthorization() } }
                    }
            } footer: {
                Text("Automatically clean the selected caches on a weekly schedule.")
            }
```

(The `When` and `Targets` sections are unchanged.)

- [ ] **Step 3: App wiring.** In `XcodeCleanerApp`, add the notifier and inject it.

```swift
    private let scheduler: Scheduler
    private let notifier = UserNotifier()

    init() {
        let vm = CleanerViewModel()
        let settings = SettingsModel()
        _vm = State(initialValue: vm)
        _settings = State(initialValue: settings)
        scheduler = Scheduler(vm: vm, settings: settings, notifier: notifier)
        scheduler.start()
    }
```

And update the Settings window content:

```swift
        Window("Xcode Cleaner Settings", id: Self.settingsWindowID) {
            SettingsView(vm: vm, settings: settings, notifier: notifier)
        }
        .windowResizability(.contentSize)
```

- [ ] **Step 4: Build + full test suite.** Build command → `** BUILD SUCCEEDED **`; test command → `** TEST SUCCEEDED **`.

- [ ] **Step 5: Manual verification.** Launch directly from `/tmp/xccdd` (see Global Constraints). Verify: General shows "Last scheduled clean: Never"; toggling Schedule on prompts for notification permission; (optionally set the schedule to the current minute to observe the banner + disabled Clean buttons and the completion notification).

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: scheduled-clean banner, last-run row, and notification permission on enable"
```

---

## Self-Review Notes

- **Spec coverage:** Notifying service + UserNotifier + FakeNotifier (Task 1); lastScheduledClean persistence + lastRunText (Task 2); isScheduledCleaning + runScheduledClean + performClean, cleanTargets removed (Task 3); scheduler records last run + notifies, FakeScanner sequence used (Tasks 3–4); banner + disabled Clean + last-run row + auth-on-enable + wiring (Task 5). All covered.
- **Placeholder scan:** none — full code given for every step.
- **Type consistency:** `runScheduledClean(named:) -> (count:Int, reclaimed:Int64)` used identically in VM, Scheduler, and tests; `notifyCleanFinished(targetCount:reclaimedBytes:)` consistent across `Notifying`, `UserNotifier`, `FakeNotifier`, Scheduler; `Scheduler.init(...notifier:)` and `SettingsView.init(...notifier:)` match their call sites; `lastScheduledClean`/`lastRunText` consistent across SettingsModel, Scheduler, view.
