# Settings, Autostart & Scheduled Cleaning — Design

**Date:** 2026-06-20
**Goal:** Add a better menu bar icon, a Settings window with a launch-at-login toggle, and a crontab-like scheduled auto-clean with per-target checkboxes and a build-process safety guard.

## Context

XcodeCleaner is a macOS 14 menu bar agent (`LSUIElement`, sandbox disabled) that lists Xcode-related caches and lets the user clean them ad-hoc. The menu bar icon is currently `trash` — generic and slightly aggressive. There is no Settings UI, no launch-at-login, and no scheduling: the user must manually open the dropdown and click each row's Clean button.

This design adds three cohesive "preferences" features in one spec:

1. **Icon** — swap `trash` for `sparkles` (the macOS "clean up" convention).
2. **Settings window + autostart** — a macOS `Settings` scene with a "Launch at login" toggle backed by `SMAppService.mainApp`.
3. **Scheduled auto-clean** — day-of-week + time matching with per-target checkboxes, an internal `Timer`, and a build-process guard that postpones cleaning by +1h while `xcodebuild`/`swift`/etc. are running.

The app is always running (the autostart toggle ensures that), so an in-process `Timer` is the scheduling mechanism — no external `cron` or `launchd` plist is needed.

## Non-goals

- Not a full cron expression parser. Granularity is one day-of-week + one HH:MM time.
- Not multi-day scheduling (e.g. "Mon/Wed/Fri"). One slot per week.
- Not runtime re-checking of XcodeBuildMCP availability (already handled in `CleanerViewModel.init`).
- Not monitoring for builds that start *during* a clean. The guard is check-at-fire only; once cleaning starts it runs to completion. (If a build starts mid-clean, the build may see missing caches — acceptable, and the same risk as the existing manual Clean button.)
- Not retry-with-shorter-interval. Postponement is always +1h, with a 24h give-up window from the original slot.
- Not touching the existing 6 `CleanupTarget` definitions, `CleanupKind`, `DiskScanning`, `Cleaning`, or `CommandRunning`.
- No `pbxproj` edits (all new files under synchronized groups). No entitlement changes (sandbox already disabled; `SMAppService.mainApp` needs no special entitlement). No new external dependencies.

## Architecture

Three new types plus a small helper on `CleanerViewModel`, following the codebase's MVVM + protocol-injection pattern. The build-check and time-matching logic are split into pure functions (like `SimctlParsing`) for direct unit testing; the orchestrator is tested via the existing `FakeCommandRunner`/`FakeScanner`/`FakeCleaner`.

```
App (XcodeCleanerApp)
 ├─ MenuBarExtra (icon: sparkles) → MenuBarView (vm, settings)
 │                                  ├─ ad-hoc scan/clean rows (unchanged)
 │                                  └─ "Settings…" button → @Environment(\.openSettings)
 ├─ Settings scene → SettingsView (vm, settings)
 │                    ├─ General tab: Launch-at-login toggle + next-run summary
 │                    └─ Schedule tab: enable toggle + day/time pickers + per-target checklist
 └─ Scheduler (started in init, owns a 60s Timer)
      ├─ reads SettingsModel (schedulingEnabled, weekday, hour, minute, enabledTargetNames)
      ├─ tick(now:): shouldFire? → isBuildProcessRunning? → vm.cleanTargets(named:)
      └─ deps: vm, settings, runner: CommandRunning = Shell()
```

### Component: `SettingsModel`

File: `XcodeCleaner/ViewModels/SettingsModel.swift`

`@MainActor @Observable final class SettingsModel`. Wraps `UserDefaults` (standard suite) for persistent settings and `SMAppService.mainApp` for launch-at-login. All setters write through to `UserDefaults` immediately so the values survive restarts.

**Init:** `init(userDefaults: UserDefaults = .standard)` — the parameter lets tests inject a `UserDefaults(suiteName:)` for isolation without polluting the host's standard defaults. Production uses the default.

**Stored properties** (all `UserDefaults`-backed):

| Property | Type | Default | Key |
|----------|------|---------|-----|
| `launchAtLogin` | `Bool` | `false` | `xclean.launchAtLogin` |
| `schedulingEnabled` | `Bool` | `false` | `xclean.schedulingEnabled` |
| `scheduleWeekday` | `Int` | `6` (Friday) | `xclean.scheduleWeekday` |
| `scheduleHour` | `Int` | `2` | `xclean.scheduleHour` |
| `scheduleMinute` | `Int` | `0` | `xclean.scheduleMinute` |
| `enabledTargetNames` | `Set<String>` | `[]` | `xclean.enabledTargetNames` |

`enabledTargetNames` is serialized as a sorted `[String]` (via `JSONEncoder`/`JSONDecoder` on `[String]`) because `UserDefaults` does not natively store `Set<String>`. Target identity is by name (e.g. `"Xcode DerivedData"`) — stable across launches since `CleanerViewModel` builds the same target list each time.

**`launchAtLogin` setter side-effect:** on transition to `true`, calls `SMAppService.mainApp.register()`; on transition to `false`, calls `unregister()`. Stores the result for potential future surfacing but does not block the UI on failure (the toggle reflects intent; `SMAppService` registration is best-effort). `SMAppService` is the modern macOS 13+ Login Items API; we target macOS 14 so it's available with no entitlement.

**Computed:** `nextRunText: String?` — uses `Calendar.current` to find the next `Date` matching `(scheduleWeekday, scheduleHour, scheduleMinute)` on or after `Date()`, formats it via `DateFormatter` (e.g. "Fri, Jun 27 at 2:00 AM"). Returns `nil` when `schedulingEnabled == false`.

### Component: `Scheduling` (pure functions)

File: `XcodeCleaner/Services/Scheduling.swift`

A namespace of pure, non-`Sendable`-irrelevant, non-throwing functions with no I/O — directly unit-testable, mirroring how `SimctlParsing` is split from `DiskScanning`.

```swift
enum Scheduling {
    static let buildProcessNames: Set<String> = [
        "xcodebuild", "swift", "swiftc", "clang", "clang++", "ld", "swift-frontend"
    ]

    /// True if the basename of `comm` (e.g. "/usr/bin/xcodebuild" → "xcodebuild")
    /// is in `buildProcessNames`.
    static func isBuildProcess(_ comm: String) -> Bool

    /// True if `now` matches the configured weekday/hour/minute AND `lastFired`
    /// is nil or before today's slot (prevents double-firing within the same minute).
    static func shouldFire(now: Date, weekday: Int, hour: Int, minute: Int, lastFired: Date?) -> Bool

    /// `from + 1 hour`, with seconds and minutes zeroed (truncates to the top of the hour).
    /// e.g. Fri 02:00:30 → Fri 03:00:00.
    static func postponedFireTime(from: Date) -> Date

    /// `originalFire + 24 hours`. The Scheduler gives up and waits for next week
    /// if it can't fire within 24h of the original slot.
    static func giveUpTime(originalFire: Date) -> Date
}
```

`shouldFire` uses `Calendar.current.component(.weekday, from: now)` (1=Sunday…7=Saturday, matching `scheduleWeekday`'s convention) and `hour`/`minute` components. The `lastFired` guard compares against the start of today's configured slot (constructed via `Calendar.current.date(bySettingHour:minute:second:of:)`) so a match within the same minute after firing returns false.

### Component: `Scheduler`

File: `XcodeCleaner/ViewModels/Scheduler.swift`

`@MainActor @Observable final class Scheduler`. Owns a 60-second `Timer` and orchestrates the weekly fire.

**Stored state:**
- `private let vm: CleanerViewModel`
- `private let settings: SettingsModel`
- `private let runner: CommandRunning` (default `Shell()`, injectable for tests)
- `private var lastFired: Date?` — the last successful clean (prevents same-slot double-fire across app restarts within the same week; reset to nil when a new week's slot passes)
- `private var pendingFire: Date?` — the postponed slot when a build was detected; nil when running on the configured schedule
- `private var originalFire: Date?` — the slot that started the current postpone chain (for the 24h give-up check); nil when not postponing
- `private var timer: Timer?`

**Methods:**
- `start()` — creates a `Timer.scheduledTimer(withTimeInterval: 60, repeats: true)` that calls `tick(now: Date())`. Retains the timer.
- `stop()` — invalidates and nils the timer.
- `tick(now: Date)` — the orchestrator (see data flow below). Internal; called by the timer and by tests.

**`tick(now:)` logic:**
1. If `!settings.schedulingEnabled` → return.
2. Compute `effectiveFire = pendingFire ?? today's slot at (settings.scheduleWeekday, settings.scheduleHour, settings.scheduleMinute)`.
3. If `!Scheduling.shouldFire(now: now, weekday: settings.scheduleWeekday, hour: settings.scheduleHour, minute: settings.scheduleMinute, lastFired: lastFired)` AND `pendingFire == nil` → return. (When `pendingFire != nil`, we always proceed to the build check — the postpone was already a shouldFire match.)
4. **Build check:** run `ps -axo comm=` via `runner.run`. Parse lines (one process name per line). Check `Scheduling.isBuildProcess` on each basename.
5. If a build is running:
   - If `pendingFire == nil` (first postponement): set `originalFire = effectiveFire`, `pendingFire = Scheduling.postponedFireTime(from: now)`. Return.
   - Else (already postponing): if `now >= Scheduling.giveUpTime(originalFire: originalFire)` → clear `pendingFire` and `originalFire` (give up until next week's slot), return. Else `pendingFire = Scheduling.postponedFireTime(from: now)`. Return.
6. No build running → call `vm.cleanTargets(named: settings.enabledTargetNames)`, set `lastFired = now`, clear `pendingFire` and `originalFire`.

### Component: `CleanerViewModel` addition

File: `XcodeCleaner/ViewModels/CleanerViewModel.swift` (modified)

Adds one helper, no existing behavior change:

```swift
func cleanTargets(named names: Set<String>) {
    for target in targets where names.contains(target.name) {
        clean(target)
    }
}
```

`clean(_:)` already exists and is unchanged; this is a thin filter+dispatch. The Scheduler calls it instead of `clean(_:)` directly so the Scheduler doesn't need to know the `CleanupTarget` list.

### Component: `SettingsView`

File: `XcodeCleaner/Views/SettingsView.swift`

A SwiftUI `View` rendered inside a `Settings` scene. Two tabs via `TabView` with `.tabViewStyle(.automatic)` (renders as a macOS toolbar tab bar).

**Tab 1: General**
- `Toggle("Launch at login", isOn: $settings.launchAtLogin)`.
- Below it, a secondary-text summary: if `settings.schedulingEnabled`, show `"Next scheduled clean: \(settings.nextRunText ?? "")"` and the enabled target names joined by ", "; else show `"Scheduling disabled"`.

**Tab 2: Schedule**
- `Toggle("Enable scheduled cleaning", isOn: $settings.schedulingEnabled)`. The remaining controls are `.disabled(!settings.schedulingEnabled)`.
- `Picker("Day", selection: $settings.scheduleWeekday)` — options Sunday(1)…Saturday(7) labeled with `Calendar.current.shortWeekdaySymbols` (index `weekday - 1`).
- `DatePicker("Time", selection: hourMinuteBinding, displayedComponents: .hourAndMinute)` — a custom `Binding<Date>` that reads `settings.scheduleHour`/`scheduleMinute` into a `Date` on `get` and writes them back on `set`. The `Date`'s year/month/day are arbitrary (fixed to today); only hour and minute matter.
- **Per-target checklist:** `ForEach(vm.targets) { target in Toggle(target.name, isOn: bindingFor(target.name)) }`. `bindingFor(name:)` returns a `Binding<Bool>` whose `get` is `settings.enabledTargetNames.contains(name)` and `set` adds/removes from the set. The checklist iterates `vm.targets`, so the conditional XcodeBuildMCP row appears here only when it appears in the dropdown — no separate availability wiring.

`SettingsView` init: `init(vm: CleanerViewModel, settings: SettingsModel)` — both injected from the app.

### Component: `MenuBarView` changes

File: `XcodeCleaner/Views/MenuBarView.swift` (modified)

- Replaces `@State private var vm = CleanerViewModel()` with `let vm: CleanerViewModel` and `let settings: SettingsModel` (injected from the app).
- Adds `@Environment(\.openSettings) private var openSettings`.
- Between the existing divider and "Quit", inserts a borderless `Button("Settings…") { openSettings() }`.

### Component: `XcodeCleanerApp` changes

File: `XcodeCleaner/App/XcodeCleanerApp.swift` (modified)

- Icon: `systemImage: "trash"` → `systemImage: "sparkles"`.
- Owns shared `@State private var vm: CleanerViewModel` and `@State private var settings: SettingsModel`.
- Holds `private let scheduler: Scheduler`, constructed and started in `init()` (so the timer is live from launch, regardless of whether the dropdown is ever opened).
- Adds a `Settings { SettingsView(vm: vm, settings: settings) }` scene alongside the existing `MenuBarExtra`.

```swift
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

## Data flow

**Ad-hoc clean (unchanged):** user opens dropdown → clicks a row's Clean → `vm.clean(target)` → `Cleaner` deletes → `DiskScanner` rescan → row updates.

**Settings change:** user opens Settings → toggles/pickers/checkboxes → `SettingsModel` setters write to `UserDefaults` immediately → `Scheduler` reads them on next `tick(now:)` (it holds a reference to the same `settings` instance). No notification bus needed — both point at the same `@Observable` object.

**Scheduled clean:**
1. `Scheduler`'s 60s `Timer` fires → `tick(now: Date())`.
2. `tick` checks `settings.schedulingEnabled`; if off, returns.
3. Checks `Scheduling.shouldFire(now:weekday:hour:minute:lastFired:)`; if no match and not postponing, returns.
4. Runs `ps -axo comm=` via `runner.run`. Parses process names.
5. If any process matches `Scheduling.isBuildProcess` → set `pendingFire = now + 1h` (truncated to top of hour); return. If past the 24h give-up window → clear `pendingFire`/`originalFire`; return.
6. No build → `vm.cleanTargets(named: settings.enabledTargetNames)` → for each enabled target, the existing `clean(_:)` path runs (state → `.cleaning` → `Cleaner` deletes → rescan → `.cleaned`). Set `lastFired = now`; clear `pendingFire`/`originalFire`.

## Error handling

- `Scheduling` pure functions: non-throwing, infallible.
- `Scheduler.tick`: `runner.run` can throw (e.g. `ps` missing — should never happen on macOS). On throw, the tick returns without firing or postponing (treats it as "couldn't determine build state, try again next minute"). No user-facing alert; the next tick retries. This matches the existing `DiskScanner`/`Cleaner` pattern of surfacing errors via `TargetState.error` rather than UI alerts — but the Scheduler has no target state to set, so it silently retries.
- `SMAppService.register/unregister`: can throw/fail (e.g. MDM restrictions). `SettingsModel.launchAtLogin` setter catches the result but does not revert the toggle or alert — the toggle reflects user intent and `UserDefaults` will re-attempt `register` on next launch. Acceptable for a personal utility; the worst case is "toggle is on but login item didn't register," which the user will notice on next reboot.
- `Cleaner.clean` failures for scheduled cleans: surface via `TargetState.error` exactly as ad-hoc cleans do. The Scheduler does not interpret or retry clean failures.

## Testing

Following the codebase's pattern — pure functions get direct unit tests; orchestrators get tested via existing fakes.

**New `SchedulingTests.swift` (6 tests, pure functions):**
- `testIsBuildProcessMatchesKnownNames` — `"xcodebuild"` → true, `"/usr/bin/xcodebuild"` → true, `"swift-frontend"` → true, `"Photos"` → false, `""` → false.
- `testShouldFireMatchesExactSlot` — `now` at Fri 02:00:30, config weekday=6/hour=2/minute=0, `lastFired=nil` → true.
- `testShouldFireRespectsLastFired` — same `now`, `lastFired` = today 02:00:00 → false.
- `testShouldFireIgnoresDifferentWeekday` — `now` at Thursday 02:00, config Friday → false.
- `testPostponedFireTimeAddsHourAndTruncatesMinutes` — `from` = Fri 02:00:30 → Fri 03:00:00.
- `testGiveUpTimeIs24HoursLater` — `originalFire` = Fri 02:00 → Sat 02:00.

**New `SchedulerTests.swift` (4 tests, `@MainActor`):**
- `testTickDoesNothingWhenSchedulingDisabled` — `settings.schedulingEnabled = false`; `tick(now:)` → `FakeCleaner.cleanedNames` empty.
- `testTickPostponesWhenBuildProcessRunning` — `FakeCommandRunner` returns `ps` output containing `xcodebuild\n`; `tick(now: fireTime)` → `pendingFire` set to +1h, `FakeCleaner.cleanedNames` empty.
- `testTickFiresWhenNoBuildProcessRunning` — `FakeCommandRunner` returns `ps` output with no build names; `settings.enabledTargetNames = ["Xcode DerivedData"]`; `tick(now: fireTime)` → `FakeCleaner.cleanedNames == ["Xcode DerivedData"]`, `lastFired` set.
- `testTickGivesUpAfter24Hours` — `pendingFire`/`originalFire` set to just before give-up; `FakeCommandRunner` returns build running → `cleanedNames` empty, `pendingFire` cleared.

Uses existing `FakeCommandRunner` (for `ps` output), `FakeScanner`, `FakeCleaner`. No new fakes needed. `Scheduler` is constructed with `vm: CleanerViewModel(scanner: FakeScanner(...), cleaner: FakeCleaner(...), availability: FakeAvailability(existsResult: true))` and `settings: SettingsModel` (using a test-specific `UserDefaults` suite via a `UserDefaults(suiteName:)`-injected initializer on `SettingsModel` for test isolation).

**New `SettingsModelTests.swift` (2 tests):**
- `testDefaultsAreSensible` — fresh `SettingsModel(userDefaults: testSuite)` → `launchAtLogin == false`, `schedulingEnabled == false`, `scheduleWeekday == 6`, `scheduleHour == 2`, `enabledTargetNames == []`.
- `testEnabledTargetNamesRoundTrips` — set `enabledTargetNames = ["Xcode DerivedData", "SwiftPM cache"]`; read back from a new `SettingsModel` on the same suite → equal set.

`SettingsModel` init takes an optional `userDefaults: UserDefaults = .standard` param so tests can inject a `UserDefaults(suiteName:)` without polluting the host.

**Existing 17 tests stay green.** `CleanerViewModel.cleanTargets(named:)` is additive; existing `scan`/`clean` tests don't touch it.

**Total: 17 + 6 + 4 + 2 = 29 tests.**

## Files touched

| File | Change |
|------|--------|
| `XcodeCleaner/App/XcodeCleanerApp.swift` | icon `trash`→`sparkles`; own shared `vm`/`settings`; add `Settings` scene; start `Scheduler` in `init` |
| `XcodeCleaner/Views/MenuBarView.swift` | accept `vm`+`settings` params; add "Settings…" button via `@Environment(\.openSettings)` |
| `XcodeCleaner/Views/SettingsView.swift` | new — two-tab Settings window (General + Schedule) |
| `XcodeCleaner/ViewModels/SettingsModel.swift` | new — `@MainActor @Observable` UserDefaults wrapper + `SMAppService` |
| `XcodeCleaner/ViewModels/Scheduler.swift` | new — `@MainActor` orchestrator with `tick(now:)` + 60s Timer |
| `XcodeCleaner/Services/Scheduling.swift` | new — pure functions: `isBuildProcess`, `shouldFire`, `postponedFireTime`, `giveUpTime`, `buildProcessNames` |
| `XcodeCleaner/ViewModels/CleanerViewModel.swift` | add `cleanTargets(named:)` helper |
| `XcodeCleanerTests/SchedulingTests.swift` | new — 6 pure-function tests |
| `XcodeCleanerTests/SchedulerTests.swift` | new — 4 orchestrator tests |
| `XcodeCleanerTests/SettingsModelTests.swift` | new — 2 settings round-trip tests |
| `README.md` | update: mention scheduling + autostart; update icon note |

No `pbxproj` edits (all new files under synchronized groups). No entitlement changes. No new external dependencies.

## Build/test commands (unchanged from project convention)

- Build: `xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6` → `** BUILD SUCCEEDED **`.
- Test: `xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10` → `** TEST SUCCEEDED **`.
