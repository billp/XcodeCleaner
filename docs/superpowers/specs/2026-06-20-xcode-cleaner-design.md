# Xcode Cleaner — Design

**Date:** 2026-06-20
**Status:** Approved

## Summary

A macOS menu bar (status item) app that surfaces the disk usage of Xcode-related
caches and lets the user reclaim space per-target. It mirrors the WireGuard menu
bar pattern: a trash icon in the top bar opens a dropdown listing each cache with
its current size and an individual **Clean** button. Cleaning a row swaps its
button for a progress spinner while deletion runs, then re-scans and shows the
new size.

## Goals

- One-glance view of how much space each Xcode cache is consuming.
- Per-target cleanup, each independent (multiple can run at once).
- Live progress feedback while a target is being cleaned.
- No Dock icon — a lightweight always-available menu bar agent.

## Non-Goals

- Scheduling / automatic cleanup.
- Sandboxed App Store distribution (needs raw `~/Library/Developer` access).
- Managing individual projects/files inside a cache (whole-cache granularity only).

## Platform & Project Shape

- **UI:** SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)` so the dropdown
  can host buttons and progress views.
- **Icon:** `trash` SF Symbol, template-rendered to match the menu bar.
- **Agent app:** `LSUIElement = true` (no Dock icon, no main window).
- **Sandbox:** disabled — the app must read/delete under `~/Library/Developer`
  and `~/Library/Caches`, and shell out to `xcrun simctl`.
- **Targets:** macOS 14+, Swift 6, Xcode project (`.xcodeproj`).
- **Bundle id:** `com.local.XcodeCleaner`. App name: **Xcode Cleaner**.

## Tracked Targets (6 rows)

| # | Name | Kind | Size measured as | Clean action |
|---|------|------|------------------|--------------|
| 1 | XcodeBuildMCP workspaces | directory | `du -sk ~/Library/Developer/XcodeBuildMCP/workspaces` | delete directory **contents** |
| 2 | Xcode DerivedData | directory | `du -sk ~/Library/Developer/Xcode/DerivedData` | delete directory **contents** |
| 3 | SwiftPM cache | directory | `du -sk ~/Library/Caches/org.swift.swiftpm` | delete directory **contents** |
| 4 | iOS DeviceSupport | directory | `du -sk ~/Library/Developer/Xcode/iOS\ DeviceSupport` | delete directory **contents** |
| 5 | Unused simulators (devices) | simulators | size of *unavailable* CoreSimulator devices | `xcrun simctl delete unavailable` |
| 6 | Unused simulator runtimes | runtimes | sum of `sizeBytes` for runtimes whose `lastUsedAt` is older than the threshold (default 30 days), from `xcrun simctl runtime list -j` | `xcrun simctl runtime delete --notUsedSinceDays <N>` |

Notes:
- Directory targets delete **contents**, not the directory itself, so Xcode / the
  MCP server simply repopulate them on next use (matches manual cleanup behavior).
- Target 5 size: parse `xcrun simctl list devices -j`, find devices in
  unavailable runtimes, sum their data-dir sizes (best-effort; if size can't be
  computed, show device count instead).
- Target 6 threshold is configurable; default 30 days. A runtime used recently
  (like the currently-installed iOS versions) is **not** counted and **not** deleted.

## Components

Each is small and single-purpose.

### `CleanupTarget` (model)
- `id`, `name`, `kind` (`.directory(path)` / `.unavailableSimulators` / `.unusedRuntimes(days)`)
- `state`: `.idle | .scanning | .scanned(bytes) | .cleaning | .done(bytes) | .error(String)`
- Convenience: human-readable size string.

### `DiskScanner`
- `func size(of: CleanupTarget) async -> Result<Int64, Error>`
- Directory: runs `du -sk` via `Process` off the main actor (fast, matches Finder-ish).
- Simulators/runtimes: runs the relevant `simctl ... -j`, parses JSON, sums bytes.

### `Cleaner`
- `func clean(_ target: CleanupTarget) async -> Result<Void, Error>`
- Directory: enumerate top-level entries, `FileManager.removeItem` each.
- Simulators: `xcrun simctl delete unavailable`.
- Runtimes: `xcrun simctl runtime delete --notUsedSinceDays <N>`.

### `AppState` (`@Observable`)
- Owns `[CleanupTarget]`.
- `scanAll()` — concurrent scan on menu open / manual refresh.
- `clean(_ target)` — sets `.cleaning`, runs `Cleaner`, then re-scans that row.
- Computes total reclaimable across scanned rows.

### `MenuBarView` + `TargetRow` (SwiftUI)
- Header: title + total reclaimable + a refresh button + Quit.
- One `TargetRow` per target: name, size (or "scanning…"), and a trailing control
  that is a **Clean** button when idle and an indeterminate `ProgressView` while
  `.cleaning`. On error, shows the message inline with a Retry.

### App entry
- `@main` `App` with a single `MenuBarExtra("Xcode Cleaner", systemImage: "trash")`
  using `.menuBarExtraStyle(.window)` and rendering `MenuBarView`.

## Data Flow

1. Menu opens → `AppState.scanAll()` runs all six scans concurrently; rows show
   "scanning…" then their size; header shows the running total.
2. User clicks a row's **Clean** → row state `.cleaning`, button becomes a spinner,
   `Cleaner` runs off the main actor.
3. On completion → row re-scans, shows the new (near-zero) size; total updates.
4. Rows are independent; several can be cleaning simultaneously.

## Error Handling

- Per-row `.error(String)` state; surfaced inline (e.g. "Directory not empty",
  "permission denied"), with a Retry. Never crashes or blocks the menu.
- A failed clean leaves other rows untouched.

## Testing

- `DiskScanner` and `Cleaner` are pure-ish wrappers around `Process`/`FileManager`;
  unit-test the JSON parsing (simulator/runtime size summation) against captured
  `simctl -j` fixtures.
- Cleaning logic tested against a temporary throwaway directory tree.
- UI verified manually: scan shows sizes, clean shows spinner then updated size.
