# Preserve In-Flight State on Menu Reopen

## Problem

When a clean is running and the user closes and reopens the menu-bar popover,
the row that was cleaning reverts to showing a scan ("scanning…") instead of
remembering its "cleaning…" state.

The underlying view-model state actually survives the close/reopen — `CleanerViewModel`
is held as app-level `@State`. The bug is the auto-rescan: `MenuBarView` has
`.onAppear { cleaner.scanAll() }`, and with `MenuBarExtra(.window)` that `onAppear`
fires on *every* reopen, not just the first. `scanAll()` calls `scan(_:)` for each
target, which unconditionally sets the target's state to `.scanning`, clobbering any
row that is mid-`.cleaning`. The clean `Task` keeps running in the background, but the
UI has discarded its "cleaning…" indicator, so it looks like the operation restarted
with a scan.

## Fix

Make `CleanerViewModel.scan(_:)` skip targets that are already busy. Add a guard at the
top that returns early when the target's state is `.scanning` or `.cleaning`:

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

Both `scanAll()` and the manual refresh button route through `scan(_:)`, so this single
guard covers every path:

- Reopening the menu (or hitting refresh) during a clean leaves that row showing
  "cleaning…".
- Idle, finished (`.scanned` / `.cleaned`), and errored rows still rescan and refresh
  their sizes as before.
- It also prevents starting a duplicate concurrent scan of a row that is already
  `.scanning`.

This matches the chosen behavior: **skip only busy rows** — the rescan still runs for
everything else.

## Scope

- One guard added to `CleanerViewModel.scan(_:)`.
- No changes to `MenuBarView`, the `cleanAll()` batch logic, or scheduled cleans
  (`runScheduledClean`).

## Testing

Add a case to `CleanerViewModelTests` using the existing `FakeScanner` / `FakeCleaner`:

- Put one target into `.cleaning` and leave another `.idle`, call `scanAll()`, then
  assert the cleaning target's state is still `.cleaning` while the idle target
  transitions toward `.scanning` / `.scanned`.
- Optionally assert that calling `scan(_:)` on an already-`.scanning` target does not
  start a second scan.
