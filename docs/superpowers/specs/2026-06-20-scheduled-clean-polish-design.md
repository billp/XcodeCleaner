# Scheduled-Clean Polish — Design

**Date:** 2026-06-20
**Status:** Approved

## Summary

Three improvements to scheduled cleaning in XcodeCleaner:

1. **Mutual exclusion** — while a scheduled clean runs, the manual **Clean**
   buttons in the menu bar are disabled and a banner is shown.
2. **Last scheduled clean** — persist and display the timestamp of the most
   recent scheduled clean in Settings.
3. **Completion notification** — post a user notification when a scheduled
   clean finishes, reporting reclaimed space and how many caches were cleaned.

Behavior-preserving for manual cleaning and existing scheduling logic except
where described.

## Decisions

- Notification permission is requested **when the user enables scheduled
  cleaning** (contextual), not at launch.
- The notification reports **reclaimed space + target count**
  (e.g. "Freed 1.2 GB across 3 caches").
- During a scheduled run, **Clean buttons are disabled and a banner shows**;
  refresh and quit remain usable.

## Components

### New service: `Notifying` (Services/Notifying.swift)
```swift
protocol Notifying: Sendable {
    func requestAuthorization() async
    func notifyCleanFinished(targetCount: Int, reclaimedBytes: Int64) async
}
```
- `UserNotifier: Notifying` wraps `UNUserNotificationCenter.current()`:
  - `requestAuthorization()` requests `[.alert, .sound]` (errors ignored — best effort).
  - `notifyCleanFinished` builds a `UNMutableNotificationContent` (title
    "Xcode Cleaner"; body "Freed \(ByteCountFormatter .file) across N cache(s).")
    and adds a request with a `nil` trigger (immediate). Singular/plural "cache".
- `FakeNotifier: Notifying` (test target) records `authorizationRequests` count
  and an array of `(targetCount, reclaimedBytes)` for `notifyCleanFinished`.

### `CleanerViewModel`
- Add observable `private(set) var isScheduledCleaning = false`.
- Extract `private func performClean(_ target: CleanupTarget) async -> Int64`:
  - Determine `before` = `target.sizeBytes`, or scan if nil.
  - Set `.cleaning`; `await cleaner.clean(target)`; on success rescan → `.cleaned(after)`
    and return `max(0, before - after)`; on failure set `.error` and return 0.
- The existing `clean(_:)` becomes `Task { _ = await performClean(target) }`.
- Add `func runScheduledClean(named names: Set<String>) async -> (count: Int, reclaimed: Int64)`:
  - `isScheduledCleaning = true` (`defer { isScheduledCleaning = false }`).
  - For each target whose name is in `names`: `reclaimed += await performClean(target)`, `count += 1`.
  - Return `(count, reclaimed)`.
- `cleanTargets(named:)` is removed; the scheduler now calls `runScheduledClean`.
  (Any test referencing `cleanTargets` is updated to `runScheduledClean`.)

### `Scheduler`
- Inject `notifier: Notifying` (default `UserNotifier()`).
- In `tick(now:)`, replace `vm.cleanTargets(named:)` with:
  ```swift
  let result = await vm.runScheduledClean(named: settings.enabledTargetNames)
  settings.lastScheduledClean = now
  await notifier.notifyCleanFinished(targetCount: result.count, reclaimedBytes: result.reclaimed)
  lastFired = now
  pendingFire = nil
  originalFire = nil
  ```
  (The build-process guard and postponement logic are unchanged.)

### `SettingsModel`
- Add persisted `lastScheduledClean: Date?` (UserDefaults key
  `xclean.lastScheduledClean`), observable via `access`/`withMutation`.
- Add computed `lastRunText: String?` → formatted "EEE, MMM d 'at' h:mm a"
  (nil when never run; the view shows "Never").

### Views
- **MenuBarView**: read `vm.isScheduledCleaning`. When true, show a banner row
  ("Scheduled clean in progress…", caption, secondary) above the targets, and
  apply `.disabled(vm.isScheduledCleaning)` to each `TargetRow` (disables its
  Clean button). Refresh and Quit are unaffected.
- **SettingsView › General**: add `LabeledContent("Last scheduled clean",
  value: settings.lastRunText ?? "Never")` in the Scheduled-cleaning section.
- **SettingsView › Schedule**: the Enable toggle uses
  `.onChange(of: settings.schedulingEnabled)`; when it becomes `true`, call
  `Task { await notifier.requestAuthorization() }`. `notifier` is passed into
  `SettingsView`/`ScheduleTab`.

### Wiring (`XcodeCleanerApp`)
- Create one `let notifier = UserNotifier()`.
- Pass it to `Scheduler(vm:settings:notifier:)` and to
  `SettingsView(vm:settings:notifier:)`.

## Data Flow

Timer tick → scheduling due + no build running → `vm.runScheduledClean` sets
`isScheduledCleaning` (menu disables Clean + shows banner) → each target
cleaned, reclaimed summed → flag cleared → scheduler records
`settings.lastScheduledClean` and posts the notification → General tab shows the
new "Last scheduled clean" value.

## Error Handling

- Per-target failures inside `performClean` set the row to `.error` and count 0
  reclaimed for that target; the batch continues. The notification still posts
  with whatever was reclaimed.
- Notification authorization denial is silent; `notifyCleanFinished` is a no-op
  if not authorized (system drops it). No crash.

## Testing

- `FakeNotifier` records auth requests and finish calls.
- `CleanerViewModelTests`: `runScheduledClean` returns the right count and
  reclaimed total (using `FakeScanner` scripted before/after sizes) and toggles
  `isScheduledCleaning` true→false.
- `SchedulerTests`: on a due tick with no build running, `runScheduledClean` is
  invoked, `settings.lastScheduledClean` is set, and `FakeNotifier` received one
  `notifyCleanFinished` with the expected count/bytes. (Existing build-guard and
  postponement tests remain green; update any `cleanTargets` reference.)
- `SettingsModelTests`: `lastScheduledClean` persists across instances; `lastRunText`
  is nil when unset.
- UI (banner, disabled buttons, Last-run row, auth-on-enable) verified manually.

## Non-Goals

- Blocking the scheduler while a manual clean is running (only the reverse is
  requested).
- Rich notification actions / deep links.
- Per-target reclaimed breakdown in the notification (aggregate only).
