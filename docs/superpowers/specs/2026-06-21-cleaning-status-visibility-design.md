# Cleaning-Status Visibility + Notification Fix — Design

**Date:** 2026-06-21
**Status:** Approved

## Summary

Make it obvious when XcodeCleaner is cleaning, and fix scheduled-clean
notifications not appearing:

1. **Unified busy state** in the view model covering both scheduled and manual
   cleans.
2. **Menu bar icon** changes while cleaning (visible without opening the dropdown).
3. **More prominent in-dropdown status banner** (spinner + bold text) for both
   scheduled and manual cleans.
4. **Notification fix**: request notification authorization on launch when
   scheduling is enabled (today it's only requested from the Schedule toggle's
   `onChange`, which never fires when scheduling is already persisted-on).

## Root cause: no scheduler notification

`SettingsModel.schedulingEnabled` persists across launches. Authorization is
requested only in `ScheduleTab`'s `.onChange(of: schedulingEnabled)` when toggled
**on**. So when scheduling is already enabled at launch (the normal case), the
`onChange` never fires and `requestAuthorization()` is never called → not
authorized → `notifyCleanFinished` is silently dropped by the system. (During
testing scheduling was set via `defaults`, bypassing the toggle entirely, so auth
was never requested.) Fix: also request authorization at app launch when
scheduling is enabled.

macOS caveat: local notifications are only delivered for a properly
launched/signed app; a binary executed directly from DerivedData (ad-hoc signed)
may not display them even when authorized. This is an environment limitation, not
a code defect; it will work in an installed/signed build. We verify what we can.

## Components

### `CleanerViewModel` (computed state)
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
`isScheduledCleaning` already exists. These are derived (no new stored state).
Because `isManualCleaning`/`isBusy`/`statusText` read `isScheduledCleaning` and
each `target.state` (both `@Observable`), SwiftUI re-renders correctly when either
changes.

### Menu bar icon (`XcodeCleanerApp`)
`MenuBarExtra` switches from the static `systemImage:` form to a `label:` view:
```swift
MenuBarExtra { MenuBarView(vm: vm) } label: {
    Image(systemName: vm.isBusy ? "sparkles" : "sparkles")
        .symbolEffect(.variableColor.iterative, isActive: vm.isBusy)
}
```
While busy the `sparkles` icon pulses via `.symbolEffect(.variableColor)`. (If the
pulse is not visible enough in the menu bar, fall back to swapping the symbol,
e.g. `arrow.triangle.2.circlepath` while busy.) The label reads the `@State vm`,
so it updates live.

### Status banner (`MenuBarView`)
Replace the current plain caption banner with a more prominent row shown when
`vm.isBusy`:
```swift
if let status = vm.statusText {
    HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text(status).font(.callout).bold()
        Spacer()
    }
    .padding(.vertical, 6).padding(.horizontal, 8)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
}
```
Shown for both scheduled and manual cleans (driven by `statusText`).

### Disable rules (`MenuBarView`)
- Scheduled run: keep `.disabled(vm.isScheduledCleaning)` on every `TargetRow`
  (unchanged).
- Manual clean: the active row already shows a spinner via its `TargetState`;
  other rows stay enabled (concurrent manual cleans are allowed). No new disabling.

### Notification authorization on launch (`XcodeCleanerApp`)
After creating `settings`/`notifier`, request authorization at launch if
scheduling is already enabled:
```swift
if settings.schedulingEnabled {
    Task { await notifier.requestAuthorization() }
}
```
Placed in `init()` after the notifier exists (or via a `.task` on the MenuBarExtra
content). The existing on-toggle request stays.

## Data Flow

A clean starts (manual `clean` sets a row to `.cleaning`, or scheduled
`runScheduledClean` sets `isScheduledCleaning`) → `isBusy`/`statusText` become
truthy → the menu bar icon pulses and the dropdown banner shows → on completion
the state clears and both revert. On launch, if scheduling is enabled,
authorization is requested so later `notifyCleanFinished` calls can be delivered.

## Error Handling

Unchanged. Authorization denial is silent; notifications simply won't show.
Derived state can't fail.

## Testing

- `CleanerViewModelTests`: `isManualCleaning`/`isBusy`/`statusText` reflect a
  target entering/leaving `.cleaning` and `isScheduledCleaning` true/false (use
  `FakeScanner`/`FakeCleaner`; drive a manual `clean` and a `runScheduledClean`).
- Auth-on-launch: a small test that constructing the app's startup path with
  scheduling enabled triggers `FakeNotifier.requestAuthorization` — implemented by
  extracting the "request auth if enabled" into a testable function
  `requestSchedulingAuthorizationIfNeeded(settings:notifier:)` and asserting it
  calls the fake when enabled and not when disabled.
- Menu bar icon + banner prominence verified manually.

## Non-Goals

- Disabling other rows during a manual clean (concurrent manual cleans allowed).
- Guaranteeing notification delivery for unsigned/dev-direct-launched builds
  (environment limitation).
- A persistent progress HUD outside the menu bar.
