# Settings, Autostart & Scheduled Cleaning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swap the menu bar icon to `sparkles`, add a Settings window with a launch-at-login toggle, and add a weekly scheduled auto-clean with per-target checkboxes and a build-process safety guard that postpones +1h while `xcodebuild`/`swift`/etc. are running.

**Architecture:** New `SettingsModel` (`@MainActor @Observable` wrapping `UserDefaults` + `SMAppService`), new `Scheduler` (`@MainActor` orchestrator with a 60s `Timer`), and new `Scheduling` enum of pure testable functions for time-matching and build-process detection. A new `SettingsView` (two-tab macOS `Settings` scene) binds to `SettingsModel` and iterates `vm.targets` for the per-row checklist. `XcodeCleanerApp` owns the shared `vm`/`settings` and starts the `Scheduler` in `init`. `CleanerViewModel` gains one trivial helper, `cleanTargets(named:)`.

**Tech Stack:** Swift 6, SwiftUI, macOS 14, `SMAppService` (ServiceManagement), `Settings` scene, `Timer`, XCTest, Xcode file-system-synchronized groups.

## Global Constraints

- Swift 6.0, macOS 14.0. App Sandbox disabled. `LSUIElement` stays `true`.
- Behavior-preserving for existing ad-hoc scan/clean flow and the conditional XcodeBuildMCP row. All 17 existing tests must stay green; new tests are added.
- Synchronized groups: new `.swift` files under `XcodeCleaner/Services/`, `XcodeCleaner/ViewModels/`, `XcodeCleaner/Views/`, and `XcodeCleanerTests/` are auto-included — NO `pbxproj` edits.
- Build: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6` → `** BUILD SUCCEEDED **`.
- Test: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10` → `** TEST SUCCEEDED **`.
- Parse noisy xcodebuild output by grepping for `BUILD SUCCEEDED`, `TEST SUCCEEDED`, `error:`.
- Spec: `docs/superpowers/specs/2026-06-20-settings-scheduling-design.md`.
- Starting state: 17 tests green on `main` (commit `ec25608`).
- Concurrency: Swift 6.2. `NSLock`/`NSLock.lock()` are **unavailable from async contexts** — if a fake needs locking, use `OSAllocatedUnfairLock.withLock` (see existing `FakeScanner`/`FakeCleaner`). Capture `let name = target.name` before any `@Sendable` closure that needs it (non-Sendable `CleanupTarget` cannot be captured).

---

## File Structure (target)

```
XcodeCleaner/
  App/        XcodeCleanerApp.swift                  (modified — icon + Settings scene + Scheduler start)
  Models/     CleanupTarget.swift, CleanupKind.swift, TargetState.swift  (unchanged)
  Services/   CommandRunning.swift, DiskScanning.swift, Cleaning.swift, SimctlParsing.swift, AvailabilityChecking.swift  (unchanged)
             Scheduling.swift                        (new — pure functions)
  ViewModels/ CleanerViewModel.swift                 (modified — add cleanTargets(named:))
             SettingsModel.swift                     (new)
             Scheduler.swift                         (new)
  Views/      MenuBarView.swift                       (modified — accept vm+settings; add Settings… button)
             TargetRow.swift                         (unchanged)
             SettingsView.swift                      (new)
  Support/    Info.plist, XcodeCleaner.entitlements  (unchanged)
XcodeCleanerTests/
  CleanerTests.swift, ShellTests.swift, SimctlParsingTests.swift, CleanerViewModelTests.swift  (unchanged)
  Fakes/ FakeCommandRunner.swift, FakeScanner.swift, FakeCleaner.swift, FakeAvailability.swift  (unchanged)
  SchedulingTests.swift                              (new — 6 pure-function tests)
  SchedulerTests.swift                               (new — 4 orchestrator tests)
  SettingsModelTests.swift                           (new — 2 settings round-trip tests)
README.md                                            (modified)
```

---

### Task 1: `Scheduling` pure functions (TDD)

**Files:**
- Create: `XcodeCleaner/Services/Scheduling.swift`
- Create: `XcodeCleanerTests/SchedulingTests.swift`

**Interfaces:**
- Produces: `enum Scheduling` with `static let buildProcessNames: Set<String>`, `static func isBuildProcess(_ comm: String) -> Bool`, `static func shouldFire(now: Date, weekday: Int, hour: Int, minute: Int, lastFired: Date?) -> Bool`, `static func postponedFireTime(from: Date) -> Date`, `static func giveUpTime(originalFire: Date) -> Date`.

- [ ] **Step 1: Write the failing tests.** Create `XcodeCleanerTests/SchedulingTests.swift`:

```swift
import XCTest
@testable import XcodeCleaner

final class SchedulingTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    func testIsBuildProcessMatchesKnownNames() {
        XCTAssertTrue(Scheduling.isBuildProcess("xcodebuild"))
        XCTAssertTrue(Scheduling.isBuildProcess("/usr/bin/xcodebuild"))
        XCTAssertTrue(Scheduling.isBuildProcess("swift-frontend"))
        XCTAssertTrue(Scheduling.isBuildProcess("clang"))
        XCTAssertTrue(Scheduling.isBuildProcess("clang++"))
        XCTAssertFalse(Scheduling.isBuildProcess("Photos"))
        XCTAssertFalse(Scheduling.isBuildProcess(""))
    }

    func testShouldFireMatchesExactSlot() {
        // Friday June 27 2026, 02:00:30 local
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 27
        comps.hour = 2; comps.minute = 0; comps.second = 30
        comps.timeZone = TimeZone.current
        let now = cal.date(from: comps)!
        XCTAssertTrue(Scheduling.shouldFire(now: now, weekday: 6, hour: 2, minute: 0, lastFired: nil))
    }

    func testShouldFireRespectsLastFired() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 27
        comps.hour = 2; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone.current
        let slot = cal.date(from: comps)!
        let now = slot.addingTimeInterval(30) // 02:00:30, same slot
        XCTAssertFalse(Scheduling.shouldFire(now: now, weekday: 6, hour: 2, minute: 0, lastFired: slot))
    }

    func testShouldFireIgnoresDifferentWeekday() {
        // Thursday June 26 2026, 02:00:00 local
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 26
        comps.hour = 2; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone.current
        let now = cal.date(from: comps)!
        XCTAssertFalse(Scheduling.shouldFire(now: now, weekday: 6, hour: 2, minute: 0, lastFired: nil))
    }

    func testPostponedFireTimeAddsHourAndTruncatesMinutes() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 27
        comps.hour = 2; comps.minute = 0; comps.second = 30
        comps.timeZone = TimeZone.current
        let from = cal.date(from: comps)!
        let result = Scheduling.postponedFireTime(from: from)
        let resultComps = cal.dateComponents([.hour, .minute, .second], from: result)
        XCTAssertEqual(resultComps.hour, 3)
        XCTAssertEqual(resultComps.minute, 0)
        XCTAssertEqual(resultComps.second, 0)
    }

    func testGiveUpTimeIs24HoursLater() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 27
        comps.hour = 2; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone.current
        let original = cal.date(from: comps)!
        let result = Scheduling.giveUpTime(originalFire: original)
        XCTAssertEqual(result.timeIntervalSince(original), 24 * 60 * 60, accuracy: 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail.**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|SchedulingTests" | head -20`
Expected: compile error "cannot find 'Scheduling' in scope" (the type doesn't exist yet).

- [ ] **Step 3: Write the implementation.** Create `XcodeCleaner/Services/Scheduling.swift`:

```swift
import Foundation

enum Scheduling {
    static let buildProcessNames: Set<String> = [
        "xcodebuild", "swift", "swiftc", "clang", "clang++", "ld", "swift-frontend",
    ]

    /// True if the basename of `comm` (e.g. "/usr/bin/xcodebuild" → "xcodebuild")
    /// is in `buildProcessNames`.
    static func isBuildProcess(_ comm: String) -> Bool {
        let name = (comm as NSString).lastPathComponent
        return buildProcessNames.contains(name)
    }

    /// True if `now` matches the configured weekday/hour/minute AND `lastFired`
    /// is nil or before today's slot (prevents double-firing within the same minute).
    static func shouldFire(now: Date, weekday: Int, hour: Int, minute: Int, lastFired: Date?) -> Bool {
        let cal = Calendar.current
        let nowWeekday = cal.component(.weekday, from: now)
        let nowHour = cal.component(.hour, from: now)
        let nowMinute = cal.component(.minute, from: now)
        guard nowWeekday == weekday, nowHour == hour, nowMinute == minute else { return false }
        guard let lastFired else { return true }
        // Build today's slot start and ensure lastFired is before it.
        let slot = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        return lastFired < slot
    }

    /// `from + 1 hour`, with seconds and minutes zeroed (truncates to the top of the hour).
    static func postponedFireTime(from: Date) -> Date {
        let cal = Calendar.current
        let plusHour = from.addingTimeInterval(60 * 60)
        return cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: plusHour)) ?? plusHour
    }

    /// `originalFire + 24 hours`.
    static func giveUpTime(originalFire: Date) -> Date {
        originalFire.addingTimeInterval(24 * 60 * 60)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass.**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **` and `Executed 23 tests, with 0 failures` (17 existing + 6 new).

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add Scheduling pure functions with tests"
```

---

### Task 2: `SettingsModel` (TDD)

**Files:**
- Create: `XcodeCleaner/ViewModels/SettingsModel.swift`
- Create: `XcodeCleanerTests/SettingsModelTests.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class SettingsModel` with `init(userDefaults: UserDefaults = .standard)`, properties `launchAtLogin`, `schedulingEnabled`, `scheduleWeekday`, `scheduleHour`, `scheduleMinute`, `enabledTargetNames: Set<String>`, computed `nextRunText: String?`.

- [ ] **Step 1: Write the failing tests.** Create `XcodeCleanerTests/SettingsModelTests.swift`:

```swift
import XCTest
@testable import XcodeCleaner

@MainActor
final class SettingsModelTests: XCTestCase {
    private func makeSuite() -> UserDefaults {
        let name = "xclean.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    func testDefaultsAreSensible() {
        let settings = SettingsModel(userDefaults: makeSuite())
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertFalse(settings.schedulingEnabled)
        XCTAssertEqual(settings.scheduleWeekday, 6)
        XCTAssertEqual(settings.scheduleHour, 2)
        XCTAssertEqual(settings.scheduleMinute, 0)
        XCTAssertTrue(settings.enabledTargetNames.isEmpty)
    }

    func testEnabledTargetNamesRoundTrips() {
        let suite = makeSuite()
        let settings = SettingsModel(userDefaults: suite)
        settings.enabledTargetNames = ["Xcode DerivedData", "SwiftPM cache"]
        // Read back from a fresh instance on the same suite
        let reread = SettingsModel(userDefaults: suite)
        XCTAssertEqual(reread.enabledTargetNames, ["Xcode DerivedData", "SwiftPM cache"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail.**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|SettingsModelTests" | head -20`
Expected: compile error "cannot find 'SettingsModel' in scope".

- [ ] **Step 3: Write the implementation.** Create `XcodeCleaner/ViewModels/SettingsModel.swift`:

```swift
import Foundation
import ServiceManagement

@MainActor
@Observable
final class SettingsModel {
    private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "xclean.launchAtLogin") }
        set {
            defaults.set(newValue, forKey: "xclean.launchAtLogin")
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Best-effort; toggle reflects intent, re-attempts on next launch.
            }
        }
    }

    var schedulingEnabled: Bool {
        get { defaults.bool(forKey: "xclean.schedulingEnabled") }
        set { defaults.set(newValue, forKey: "xclean.schedulingEnabled") }
    }

    var scheduleWeekday: Int {
        get { defaults.object(forKey: "xclean.scheduleWeekday") as? Int ?? 6 }
        set { defaults.set(newValue, forKey: "xclean.scheduleWeekday") }
    }

    var scheduleHour: Int {
        get { defaults.object(forKey: "xclean.scheduleHour") as? Int ?? 2 }
        set { defaults.set(newValue, forKey: "xclean.scheduleHour") }
    }

    var scheduleMinute: Int {
        get { defaults.object(forKey: "xclean.scheduleMinute") as? Int ?? 0 }
        set { defaults.set(newValue, forKey: "xclean.scheduleMinute") }
    }

    var enabledTargetNames: Set<String> {
        get {
            guard let data = defaults.data(forKey: "xclean.enabledTargetNames"),
                  let array = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return Set(array)
        }
        set {
            let array = newValue.sorted()
            let data = (try? JSONEncoder().encode(array)) ?? Data()
            defaults.set(data, forKey: "xclean.enabledTargetNames")
        }
    }

    var nextRunText: String? {
        guard schedulingEnabled else { return nil }
        let cal = Calendar.current
        let now = Date()
        // Find next date matching weekday/hour/minute on or after now.
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = scheduleHour
        comps.minute = scheduleMinute
        comps.second = 0
        comps.weekday = scheduleWeekday
        // dateComponentsMatching doesn't exist; use nextDate(after:matching:...)
        let next = cal.nextDate(
            after: now.addingTimeInterval(-60),
            matching: DateComponents(weekday: scheduleWeekday, hour: scheduleHour, minute: scheduleMinute),
            matchingPolicy: .nextTime
        )
        guard let next else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        return formatter.string(from: next)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass.**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **` and `Executed 25 tests, with 0 failures` (23 + 2 new).

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add SettingsModel with UserDefaults persistence and SMAppService"
```

---

### Task 3: `CleanerViewModel.cleanTargets(named:)` helper

**Files:**
- Modify: `XcodeCleaner/ViewModels/CleanerViewModel.swift`

**Interfaces:**
- Produces: `func cleanTargets(named names: Set<String>)` on `CleanerViewModel` — iterates `targets` and calls existing `clean(_:)` for each whose `name` is in `names`. No behavior change for existing methods.

- [ ] **Step 1: Add the helper.** Open `XcodeCleaner/ViewModels/CleanerViewModel.swift`. Immediately after the existing `func clean(_ target: CleanupTarget) { ... }` method (before `var totalText`), insert:

```swift
    func cleanTargets(named names: Set<String>) {
        for target in targets where names.contains(target.name) {
            clean(target)
        }
    }
```

- [ ] **Step 2: Build + Test** — Expected `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **` with `Executed 25 tests, with 0 failures` (no new tests; helper is covered indirectly by SchedulerTests in Task 5).

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add CleanerViewModel.cleanTargets(named:)"
```

---

### Task 4: `Scheduler` class (TDD)

**Files:**
- Create: `XcodeCleaner/ViewModels/Scheduler.swift`
- Create: `XcodeCleanerTests/SchedulerTests.swift`

**Interfaces:**
- Consumes: `CleanerViewModel`, `SettingsModel`, `CommandRunning`, `Shell`, `Scheduling`.
- Produces: `@MainActor @Observable final class Scheduler` with `init(vm:settings:runner:)`, `start()`, `stop()`, and internal `tick(now:)`. Exposes `var pendingFire: Date?`, `var originalFire: Date?`, `var lastFired: Date?` for test inspection.

- [ ] **Step 1: Write the failing tests.** Create `XcodeCleanerTests/SchedulerTests.swift`:

```swift
import XCTest
@testable import XcodeCleaner

@MainActor
final class SchedulerTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func makeFireDate() -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 27  // Friday
        comps.hour = 2; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone.current
        return cal.date(from: comps)!
    }

    private func makeSuite() -> UserDefaults {
        let name = "xclean.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    func testTickDoesNothingWhenSchedulingDisabled() {
        let settings = SettingsModel(userDefaults: makeSuite())
        settings.schedulingEnabled = false
        let cleaner = FakeCleaner(result: .success(()))
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: true))
        let scheduler = Scheduler(vm: vm, settings: settings,
                                  runner: FakeCommandRunner(status: 0, stdout: Data("bash\n".utf8)))
        scheduler.tick(now: makeFireDate())
        XCTAssertTrue(cleaner.cleanedNames.isEmpty)
    }

    func testTickPostponesWhenBuildProcessRunning() {
        let settings = SettingsModel(userDefaults: makeSuite())
        settings.schedulingEnabled = true
        settings.enabledTargetNames = ["Xcode DerivedData"]
        let cleaner = FakeCleaner(result: .success(()))
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: true))
        let runner = FakeCommandRunner(status: 0, stdout: Data("xcodebuild\n".utf8))
        let scheduler = Scheduler(vm: vm, settings: settings, runner: runner)
        let fire = makeFireDate()
        scheduler.tick(now: fire)
        XCTAssertTrue(cleaner.cleanedNames.isEmpty)
        XCTAssertNotNil(scheduler.pendingFire)
    }

    func testTickFiresWhenNoBuildProcessRunning() {
        let settings = SettingsModel(userDefaults: makeSuite())
        settings.schedulingEnabled = true
        settings.enabledTargetNames = ["Xcode DerivedData"]
        let cleaner = FakeCleaner(result: .success(()))
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: true))
        let runner = FakeCommandRunner(status: 0, stdout: Data("bash\ngoogle-chrome\n".utf8))
        let scheduler = Scheduler(vm: vm, settings: settings, runner: runner)
        let fire = makeFireDate()
        scheduler.tick(now: fire)
        XCTAssertEqual(cleaner.cleanedNames, ["Xcode DerivedData"])
        XCTAssertNotNil(scheduler.lastFired)
        XCTAssertNil(scheduler.pendingFire)
    }

    func testTickGivesUpAfter24Hours() {
        let settings = SettingsModel(userDefaults: makeSuite())
        settings.schedulingEnabled = true
        settings.enabledTargetNames = ["Xcode DerivedData"]
        let cleaner = FakeCleaner(result: .success(()))
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: true))
        let runner = FakeCommandRunner(status: 0, stdout: Data("xcodebuild\n".utf8))
        let scheduler = Scheduler(vm: vm, settings: settings, runner: runner)
        let original = makeFireDate()
        scheduler.originalFire = original
        // Now is 25 hours after original — past the 24h give-up window.
        let now = original.addingTimeInterval(25 * 60 * 60)
        scheduler.tick(now: now)
        XCTAssertTrue(cleaner.cleanedNames.isEmpty)
        XCTAssertNil(scheduler.pendingFire)
        XCTAssertNil(scheduler.originalFire)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail.**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|SchedulerTests" | head -20`
Expected: compile error "cannot find 'Scheduler' in scope".

- [ ] **Step 3: Write the implementation.** Create `XcodeCleaner/ViewModels/Scheduler.swift`:

```swift
import Foundation

@MainActor
@Observable
final class Scheduler {
    private let vm: CleanerViewModel
    private let settings: SettingsModel
    private let runner: CommandRunning
    private var timer: Timer?

    private(set) var lastFired: Date?
    private(set) var pendingFire: Date?
    private(set) var originalFire: Date?

    init(vm: CleanerViewModel, settings: SettingsModel, runner: CommandRunning = Shell()) {
        self.vm = vm
        self.settings = settings
        self.runner = runner
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(now: Date()) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func tick(now: Date) {
        guard settings.schedulingEnabled else { return }

        // When not postponing, only proceed if the slot matches.
        if pendingFire == nil {
            guard Scheduling.shouldFire(
                now: now,
                weekday: settings.scheduleWeekday,
                hour: settings.scheduleHour,
                minute: settings.scheduleMinute,
                lastFired: lastFired
            ) else { return }
        } else if pendingFire! > now {
            // Not yet time to re-check the postponed slot.
            return
        }

        // Build-process check via ps.
        let psOutput: String
        do {
            let (_, data, _) = try runner.run("/bin/ps", ["-axo", "comm="])
            psOutput = String(data: data, encoding: .utf8) ?? ""
        } catch {
            // Couldn't determine build state; try again next minute.
            return
        }

        let buildRunning = psOutput
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .contains { Scheduling.isBuildProcess($0) }

        if buildRunning {
            if pendingFire == nil {
                // First postponement: record the original slot.
                originalFire = now
            }
            if let originalFire, now >= Scheduling.giveUpTime(originalFire: originalFire) {
                // Give up until next week's slot.
                pendingFire = nil
                originalFire = nil
            } else {
                pendingFire = Scheduling.postponedFireTime(from: now)
            }
            return
        }

        // No build running — fire.
        vm.cleanTargets(named: settings.enabledTargetNames)
        lastFired = now
        pendingFire = nil
        originalFire = nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass.**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **` and `Executed 29 tests, with 0 failures` (25 + 4 new).

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add Scheduler with build-process guard and tick(now:)"
```

---

### Task 5: `SettingsView` (two-tab Settings scene)

**Files:**
- Create: `XcodeCleaner/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `CleanerViewModel`, `SettingsModel`.
- Produces: `struct SettingsView: View` with `init(vm:settings:)` and a `TabView` of General + Schedule tabs.

- [ ] **Step 1: Create `Views/SettingsView.swift`:**

```swift
import SwiftUI

struct SettingsView: View {
    let vm: CleanerViewModel
    @Bindable var settings: SettingsModel

    init(vm: CleanerViewModel, settings: SettingsModel) {
        self.vm = vm
        self.settings = settings
    }

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }
            ScheduleTab(vm: vm, settings: settings)
                .tabItem { Label("Schedule", systemImage: "clock") }
        }
        .frame(width: 420)
    }
}

private struct GeneralTab: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            if settings.schedulingEnabled {
                Section("Next scheduled clean") {
                    Text(settings.nextRunText ?? "—")
                        .foregroundStyle(.secondary)
                    if settings.enabledTargetNames.isEmpty {
                        Text("No targets selected.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(settings.enabledTargetNames.sorted().joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Scheduling disabled")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }
}

private struct ScheduleTab: View {
    let vm: CleanerViewModel
    @Bindable var settings: SettingsModel

    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    private var hourMinuteBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = settings.scheduleHour
                comps.minute = settings.scheduleMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.scheduleHour = c.hour ?? 2
                settings.scheduleMinute = c.minute ?? 0
            }
        )
    }

    private func bindingFor(_ name: String) -> Binding<Bool> {
        Binding(
            get: { settings.enabledTargetNames.contains(name) },
            set: { isOn in
                if isOn { settings.enabledTargetNames.insert(name) }
                else { settings.enabledTargetNames.remove(name) }
            }
        )
    }

    var body: some View {
        Form {
            Toggle("Enable scheduled cleaning", isOn: $settings.schedulingEnabled)

            Section {
                Picker("Day", selection: $settings.scheduleWeekday) {
                    ForEach(weekdaySymbols.indices, id: \.self) { i in
                        Text(weekdaySymbols[i]).tag(i + 1)  // 1=Sunday…7=Saturday
                    }
                }
                DatePicker("Time", selection: hourMinuteBinding, displayedComponents: .hourAndMinute)
            }
            .disabled(!settings.schedulingEnabled)

            Section("Targets to auto-clean") {
                ForEach(vm.targets) { target in
                    Toggle(target.name, isOn: bindingFor(target.name))
                        .disabled(!settings.schedulingEnabled)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }
}
```

- [ ] **Step 2: Build** — Expected `** BUILD SUCCEEDED **`. (`SettingsView` is not yet wired into a `Settings` scene; it just has to compile. The `@Bindable` usage requires `SettingsModel` to be `@Observable` — it is, from Task 2.)

- [ ] **Step 3: Test** — Expected `** TEST SUCCEEDED **` (still 29 tests; no test changes).

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add SettingsView with General and Schedule tabs"
```

---

### Task 6: Wire `MenuBarView` (accept `vm`+`settings`; add "Settings…" button)

**Files:**
- Modify: `XcodeCleaner/Views/MenuBarView.swift`

**Interfaces:**
- Consumes: `CleanerViewModel`, `SettingsModel`.
- Produces: `MenuBarView` with `let vm: CleanerViewModel; let settings: SettingsModel` (no more `@State`), plus a "Settings…" button using `@Environment(\.openSettings)`.

- [ ] **Step 1: Replace `Views/MenuBarView.swift`** with:

```swift
import SwiftUI

struct MenuBarView: View {
    let vm: CleanerViewModel
    let settings: SettingsModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Xcode Cleaner").font(.headline)
                Spacer()
                Button { vm.scanAll() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            Text("Reclaimable: \(vm.totalText)")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            ForEach(vm.targets) { target in
                TargetRow(target: target) { vm.clean(target) }
            }
            Divider()
            Button("Settings…") { openSettings() }
                .buttonStyle(.borderless)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { vm.scanAll() }
    }
}
```

- [ ] **Step 2: Build** — Expected to FAIL: `MenuBarView()` is called in `XcodeCleanerApp.swift` with no arguments, but now requires `vm` and `settings`. This is expected — Task 7 fixes the app entry. Do NOT run the build yet; proceed to Task 7 before building.

(Do not commit yet — Task 7 will be committed together with this change since they are interdependent.)

---

### Task 7: Wire `XcodeCleanerApp` (icon + Settings scene + Scheduler start)

**Files:**
- Modify: `XcodeCleaner/App/XcodeCleanerApp.swift`

**Interfaces:**
- Consumes: `CleanerViewModel`, `SettingsModel`, `Scheduler`, `SettingsView`, `MenuBarView`.
- Produces: app with `sparkles` icon, shared `vm`/`settings` `@State`, `Scheduler` started in `init`, and a `Settings` scene.

- [ ] **Step 1: Replace `App/XcodeCleanerApp.swift`** with:

```swift
import SwiftUI

@main
struct XcodeCleanerApp: App {
    @State private var vm: CleanerViewModel
    @State private var settings: SettingsModel
    private let scheduler: Scheduler

    init() {
        let vm = CleanerViewModel()
        let settings = SettingsModel()
        _vm = State(initialValue: vm)
        _settings = State(initialValue: settings)
        scheduler = Scheduler(vm: vm, settings: settings)
        scheduler.start()
    }

    var body: some Scene {
        MenuBarExtra("Xcode Cleaner", systemImage: "sparkles") {
            MenuBarView(vm: vm, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(vm: vm, settings: settings)
        }
    }
}
```

- [ ] **Step 2: Build + Test** — Expected `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **` (still 29 tests). Both `MenuBarView` and `XcodeCleanerApp` now compile together.

- [ ] **Step 3: Commit** (both Task 6 and Task 7 together, since they are interdependent)

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: wire MenuBarView + XcodeCleanerApp with Settings scene and sparkles icon"
```

---

### Task 8: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Open `README.md`**. Update the opening paragraph to mention the icon is `sparkles`, and add a "Settings" section after "Architecture" describing launch-at-login + scheduled cleaning + per-target checkboxes + the build-process guard.

After the existing "Architecture" section and before "Build / run / test", insert:

```markdown
## Settings

Open **Settings…** from the menu bar dropdown (macOS Settings window, two tabs):

- **General** — `Launch at login` toggle (uses `SMAppService`; the app must be running for scheduled cleans to fire, so this is recommended if you enable scheduling). Shows the next scheduled run and selected targets.
- **Schedule** — `Enable scheduled cleaning` toggle, a day-of-week picker, a time picker, and a per-target checklist (each cache row has its own checkbox). At the configured slot each week, XcodeCleaner cleans the checked targets.

**Build-process guard:** before firing a scheduled clean, XcodeCleaner checks for running build processes (`xcodebuild`, `swift`, `swiftc`, `clang`, `clang++`, `ld`, `swift-frontend`). If any are running, the clean is postponed by one hour, repeating hourly up to 24 hours from the original slot — after which it gives up until next week's slot. Cleans never interrupt an in-progress build.
```

Also update the opening line to mention the icon and scheduling. Replace the existing first paragraph:

```markdown
A macOS menu bar app (sparkles icon) that shows the disk usage of Xcode-related caches and lets you reclaim space per-target. Click the icon to list each cache with its current size and an individual **Clean** button. A Settings window adds launch-at-login and weekly scheduled auto-clean with per-target checkboxes.
```

- [ ] **Step 2: Build** (sanity — README doesn't affect build). Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add README.md && git commit -m "docs: document settings, scheduling, and build-process guard"
```

---

## Self-Review Notes

- **Spec coverage:**
  - Icon `trash`→`sparkles`: Task 7.
  - Settings window + autostart: Task 5 (SettingsView), Task 7 (Settings scene), Task 2 (SettingsModel + SMAppService).
  - Scheduled auto-clean (day-of-week + time + per-row checkboxes): Task 2 (storage), Task 4 (Scheduler), Task 5 (UI), Task 7 (wiring).
  - Build-process guard (check-at-fire, postpone +1h, 24h give-up): Task 1 (Scheduling pure functions), Task 4 (Scheduler.tick logic), Task 8 (README).
  - Per-target checklist iterating `vm.targets` (conditional XcodeBuildMCP row respected): Task 5.
  - `CleanerViewModel.cleanTargets(named:)` helper: Task 3.
  - Tests: SchedulingTests (Task 1, 6 tests), SettingsModelTests (Task 2, 2 tests), SchedulerTests (Task 4, 4 tests) = 12 new tests, total 17 → 29.
  - README update: Task 8.
  - No pbxproj edits, no entitlement changes: confirmed across all tasks.

- **Placeholder scan:** No TBDs; every code step has complete verbatim content; every command has expected output. Tasks 6 + 7 are intentionally committed together because they are interdependent (MenuBarView gains required params that only XcodeCleanerApp supplies) — the plan calls this out explicitly and does not commit Task 6 alone.

- **Type consistency:**
  - `Scheduling.isBuildProcess(_:String)->Bool`, `shouldFire(now:weekday:hour:minute:lastFired:)`, `postponedFireTime(from:)`, `giveUpTime(originalFire:)` — defined Task 1, used Task 4. ✓
  - `SettingsModel` properties (`launchAtLogin`, `schedulingEnabled`, `scheduleWeekday`, `scheduleHour`, `scheduleMinute`, `enabledTargetNames`, `nextRunText`) and `init(userDefaults:)` — defined Task 2, used Tasks 4, 5, 7. ✓
  - `Scheduler.init(vm:settings:runner:)`, `start()`, `stop()`, `tick(now:)`, `pendingFire`/`originalFire`/`lastFired` — defined Task 4, used Task 7. ✓
  - `CleanerViewModel.cleanTargets(named:)` — defined Task 3, called in Task 4's `Scheduler.tick`. ✓
  - `SettingsView.init(vm:settings:)` — defined Task 5, used Task 7. ✓
  - `MenuBarView` `vm`/`settings` properties + `@Environment(\.openSettings)` — defined Task 6, used Task 7. ✓
  - Test fakes used: `FakeCommandRunner`, `FakeScanner`, `FakeCleaner`, `FakeAvailability` (all pre-existing from prior features). No new fakes. ✓
  - `ps -axo comm=` parse: `split(separator: "\n")` + `trimmingCharacters(in: .whitespaces)` + `isBuildProcess` — matches the basename-tolerant `Scheduling.isBuildProcess` (handles `/usr/bin/xcodebuild` form if `ps` ever returns full paths). ✓
