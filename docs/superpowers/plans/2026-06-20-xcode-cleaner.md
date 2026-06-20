# Xcode Cleaner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app that shows the disk usage of Xcode caches and lets the user clean each one independently, with live progress.

**Architecture:** SwiftUI `MenuBarExtra` agent app (no Dock icon). An `@Observable` `AppState` owns six `CleanupTarget`s. `DiskScanner` computes sizes (via `du` and `xcrun simctl … -j`); `Cleaner` deletes (via `FileManager` and `xcrun simctl`). Pure JSON-parsing helpers in `SimctlParsing` are unit-tested; scanning/cleaning/UI are verified by building and running.

**Tech Stack:** Swift 6, SwiftUI, macOS 14+, hand-written `.xcodeproj` using file-system-synchronized groups (Xcode 16+ format). `Process` shelling out to `/usr/bin/du` and `/usr/bin/xcrun`.

## Global Constraints

- macOS deployment target: **14.0**. Swift language version: **6**.
- App is an agent: `LSUIElement = true` (Info.plist), no main `WindowGroup`.
- App Sandbox **disabled** (entitlements) — needs `~/Library/Developer` + `~/Library/Caches` access and `Process`.
- Menu bar icon: SF Symbol **`trash`**, `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
- Bundle id: `com.local.XcodeCleaner`. Product/app name: **XcodeCleaner**.
- Directory targets delete directory **contents**, never the directory itself.
- All `Process` invocations run off the main actor; UI state changes hop back to `@MainActor`.
- Tracked target paths (verbatim):
  - `~/Library/Developer/XcodeBuildMCP/workspaces`
  - `~/Library/Developer/Xcode/DerivedData`
  - `~/Library/Caches/org.swift.swiftpm`
  - `~/Library/Developer/Xcode/iOS DeviceSupport`
  - Unavailable simulator devices → `xcrun simctl delete unavailable`
  - Unused runtimes (default 30 days) → `xcrun simctl runtime delete --notUsedSinceDays 30`

---

## File Structure

```
XcodeCleaner/
  XcodeCleaner.xcodeproj/project.pbxproj
  XcodeCleaner/                       (app target, synchronized folder)
    XcodeCleanerApp.swift             App entry: MenuBarExtra + trash icon
    AppState.swift                    @Observable orchestrator
    CleanupTarget.swift               Model + state enum + size formatting
    SimctlParsing.swift               Pure JSON parsing (unit-tested)
    DiskScanner.swift                 Async size computation
    Cleaner.swift                     Async deletion
    MenuBarView.swift                 Dropdown root view
    TargetRow.swift                   One row: name + size + Clean/spinner
    Info.plist                        LSUIElement = true
    XcodeCleaner.entitlements         Sandbox disabled
  XcodeCleanerTests/                  (unit test target, synchronized folder)
    SimctlParsingTests.swift          Fixtures + assertions
```

---

### Task 1: Xcode project scaffold that launches a trash menu bar icon

**Files:**
- Create: `XcodeCleaner/XcodeCleaner.xcodeproj/project.pbxproj`
- Create: `XcodeCleaner/XcodeCleaner/Info.plist`
- Create: `XcodeCleaner/XcodeCleaner/XcodeCleaner.entitlements`
- Create: `XcodeCleaner/XcodeCleaner/XcodeCleanerApp.swift`
- Create: `XcodeCleaner/XcodeCleanerTests/SimctlParsingTests.swift` (placeholder so the synchronized test folder is non-empty)

**Interfaces:**
- Produces: a buildable scheme `XcodeCleaner`; an app bundle whose menu bar shows a `trash` icon opening an empty `.window` dropdown.

- [ ] **Step 1: Write `Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>$(MACOSX_DEPLOYMENT_TARGET)</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
```

- [ ] **Step 2: Write `XcodeCleaner.entitlements`** (sandbox off)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><false/>
</dict>
</plist>
```

- [ ] **Step 3: Write minimal `XcodeCleanerApp.swift`**

```swift
import SwiftUI

@main
struct XcodeCleanerApp: App {
    var body: some Scene {
        MenuBarExtra("Xcode Cleaner", systemImage: "trash") {
            Text("Xcode Cleaner")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 4: Write placeholder test file** `XcodeCleanerTests/SimctlParsingTests.swift`

```swift
import XCTest

final class SimctlParsingTests: XCTestCase {
    func testPlaceholder() { XCTAssertTrue(true) }
}
```

- [ ] **Step 5: Write `project.pbxproj`** using file-system-synchronized groups (object version 77). Two targets: app + unit tests. Use the synchronized-root-group format so source files are picked up from the folders automatically. (Full pbxproj authored during execution following this structure: `PBXProject` → `XcodeCleaner` app target with `PBXFileSystemSynchronizedRootGroup` pointing at `XcodeCleaner/`, and `XcodeCleanerTests` target pointing at `XcodeCleanerTests/`; build settings carry `MACOSX_DEPLOYMENT_TARGET=14.0`, `SWIFT_VERSION=6.0`, `PRODUCT_BUNDLE_IDENTIFIER=com.local.XcodeCleaner`, `CODE_SIGN_ENTITLEMENTS=XcodeCleaner/XcodeCleaner.entitlements`, `INFOPLIST_FILE=XcodeCleaner/Info.plist`, `GENERATE_INFOPLIST_FILE=NO`, `CODE_SIGN_IDENTITY="-"`.)

- [ ] **Step 6: Build**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner -configuration Debug build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Launch and verify the icon**

Run: `open ~/Library/Developer/Xcode/DerivedData/XcodeCleaner-*/Build/Products/Debug/XcodeCleaner.app`
Expected: a `trash` icon appears in the menu bar; clicking shows a small window reading "Xcode Cleaner". Then `killall XcodeCleaner`.

- [ ] **Step 8: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: scaffold XcodeCleaner menu bar app"
```

---

### Task 2: `CleanupTarget` model + state + size formatting

**Files:**
- Create: `XcodeCleaner/XcodeCleaner/CleanupTarget.swift`
- Test: `XcodeCleaner/XcodeCleanerTests/SimctlParsingTests.swift` (add model assertions; rename file later if desired)

**Interfaces:**
- Produces:
  - `enum CleanupKind: Equatable { case directory(path: String); case unavailableSimulators; case unusedRuntimes(days: Int) }`
  - `enum TargetState: Equatable { case idle, scanning, scanned(Int64), cleaning, cleaned(Int64), error(String) }`
  - `@Observable final class CleanupTarget: Identifiable { let id: UUID; let name: String; let kind: CleanupKind; var state: TargetState; var sizeBytes: Int64?; var sizeText: String }`

- [ ] **Step 1: Write the failing test** (append to `SimctlParsingTests.swift`)

```swift
func testSizeTextFormatsScannedBytes() {
    let t = CleanupTarget(name: "X", kind: .unavailableSimulators)
    t.state = .scanned(1_500_000_000)
    XCTAssertEqual(t.sizeBytes, 1_500_000_000)
    XCTAssertTrue(t.sizeText.contains("GB"))
}

func testSizeTextIdleAndScanning() {
    let t = CleanupTarget(name: "X", kind: .unavailableSimulators)
    XCTAssertEqual(t.sizeText, "—")
    t.state = .scanning
    XCTAssertEqual(t.sizeText, "scanning…")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: FAIL — `CleanupTarget` undefined.

- [ ] **Step 3: Implement `CleanupTarget.swift`**

```swift
import Foundation

enum CleanupKind: Equatable {
    case directory(path: String)
    case unavailableSimulators
    case unusedRuntimes(days: Int)
}

enum TargetState: Equatable {
    case idle
    case scanning
    case scanned(Int64)
    case cleaning
    case cleaned(Int64)
    case error(String)
}

@Observable
final class CleanupTarget: Identifiable {
    let id = UUID()
    let name: String
    let kind: CleanupKind
    var state: TargetState = .idle

    init(name: String, kind: CleanupKind) {
        self.name = name
        self.kind = kind
    }

    var sizeBytes: Int64? {
        switch state {
        case .scanned(let b), .cleaned(let b): return b
        default: return nil
        }
    }

    var sizeText: String {
        switch state {
        case .idle: return "—"
        case .scanning: return "scanning…"
        case .cleaning: return "cleaning…"
        case .scanned(let b), .cleaned(let b):
            return ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
        case .error: return "error"
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add CleanupTarget model and size formatting"
```

---

### Task 3: `SimctlParsing` pure functions (TDD with fixtures)

**Files:**
- Create: `XcodeCleaner/XcodeCleaner/SimctlParsing.swift`
- Test: `XcodeCleaner/XcodeCleanerTests/SimctlParsingTests.swift`

**Interfaces:**
- Produces:
  - `enum SimctlParsing`
  - `static func unusedRuntimeBytes(json: Data, days: Int, now: Date) throws -> Int64`
  - `static func unavailableDeviceUDIDs(json: Data) throws -> [String]`

- [ ] **Step 1: Write failing tests**

```swift
func testUnusedRuntimeBytesExcludesRecentlyUsed() throws {
    let json = """
    {
      "A": { "sizeBytes": 8000000000, "lastUsedAt": "2026-06-20T12:00:00Z" },
      "B": { "sizeBytes": 7000000000, "lastUsedAt": "2026-01-01T12:00:00Z" },
      "C": { "sizeBytes": 1000000000 }
    }
    """.data(using: .utf8)!
    let now = ISO8601DateFormatter().date(from: "2026-06-20T13:00:00Z")!
    // 30-day cutoff: A is recent (keep); B is old (delete); C has no date (delete)
    let bytes = try SimctlParsing.unusedRuntimeBytes(json: json, days: 30, now: now)
    XCTAssertEqual(bytes, 8_000_000_000)
}

func testUnavailableDeviceUDIDs() throws {
    let json = """
    { "devices": {
      "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
        { "udid": "AAA", "isAvailable": true },
        { "udid": "BBB", "isAvailable": false }
      ],
      "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
        { "udid": "CCC", "availabilityError": "runtime profile not found" }
      ]
    } }
    """.data(using: .utf8)!
    let udids = try SimctlParsing.unavailableDeviceUDIDs(json: json).sorted()
    XCTAssertEqual(udids, ["BBB", "CCC"])
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: FAIL — `SimctlParsing` undefined.

- [ ] **Step 3: Implement `SimctlParsing.swift`**

```swift
import Foundation

enum SimctlParsing {
    /// Sum sizeBytes of runtimes not used within the last `days` days.
    /// Runtimes with no lastUsedAt are treated as unused.
    static func unusedRuntimeBytes(json: Data, days: Int, now: Date = Date()) throws -> Int64 {
        struct Runtime: Decodable { let sizeBytes: Int64?; let lastUsedAt: String? }
        let map = try JSONDecoder().decode([String: Runtime].self, from: json)
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let fmt = ISO8601DateFormatter()
        var total: Int64 = 0
        for rt in map.values {
            guard let size = rt.sizeBytes else { continue }
            if let s = rt.lastUsedAt, let used = fmt.date(from: s), used >= cutoff {
                continue // recently used → keep
            }
            total += size
        }
        return total
    }

    /// UDIDs of devices that are unavailable (isAvailable == false or availabilityError present).
    static func unavailableDeviceUDIDs(json: Data) throws -> [String] {
        struct Root: Decodable { let devices: [String: [Device]] }
        struct Device: Decodable {
            let udid: String
            let isAvailable: Bool?
            let availabilityError: String?
        }
        let root = try JSONDecoder().decode(Root.self, from: json)
        var result: [String] = []
        for list in root.devices.values {
            for d in list {
                let unavailable = (d.isAvailable == false) || (d.availabilityError != nil)
                if unavailable { result.append(d.udid) }
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add SimctlParsing pure helpers with tests"
```

---

### Task 4: `DiskScanner` — async sizes

**Files:**
- Create: `XcodeCleaner/XcodeCleaner/DiskScanner.swift`

**Interfaces:**
- Consumes: `CleanupTarget`, `SimctlParsing`.
- Produces:
  - `struct DiskScanner { func size(of target: CleanupTarget) async -> Result<Int64, Error> }`
  - Internal `Shell.run(_ launchPath: String, _ args: [String]) async throws -> (status: Int32, stdout: Data)`

- [ ] **Step 1: Implement `DiskScanner.swift`** (includes the shared `Shell` helper used by `Cleaner` too)

```swift
import Foundation

enum ScanError: Error, Equatable { case process(String) }

enum Shell {
    /// Runs a process off the caller's actor, returns exit status + stdout bytes.
    static func run(_ launchPath: String, _ args: [String]) async throws -> (status: Int32, stdout: Data) {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: launchPath)
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            p.terminationHandler = { proc in
                let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
                cont.resume(returning: (proc.terminationStatus, data ?? Data()))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}

struct DiskScanner {
    func size(of target: CleanupTarget) async -> Result<Int64, Error> {
        do {
            switch target.kind {
            case .directory(let path):
                return .success(try await directoryBytes(expand(path)))
            case .unavailableSimulators:
                return .success(try await unavailableSimulatorBytes())
            case .unusedRuntimes(let days):
                return .success(try await unusedRuntimeBytes(days: days))
            }
        } catch { return .failure(error) }
    }

    private func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// `du -sk` → kilobytes; 0 if the path doesn't exist.
    private func directoryBytes(_ path: String) async throws -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let (_, data) = try await Shell.run("/usr/bin/du", ["-sk", path])
        guard let text = String(data: data, encoding: .utf8),
              let kbStr = text.split(separator: "\t").first,
              let kb = Int64(kbStr.trimmingCharacters(in: .whitespaces)) else {
            return 0
        }
        return kb * 1024
    }

    private func unusedRuntimeBytes(days: Int) async throws -> Int64 {
        let (_, data) = try await Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
        guard !data.isEmpty else { return 0 }
        return try SimctlParsing.unusedRuntimeBytes(json: data, days: days)
    }

    private func unavailableSimulatorBytes() async throws -> Int64 {
        let (_, data) = try await Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"])
        guard !data.isEmpty else { return 0 }
        let udids = try SimctlParsing.unavailableDeviceUDIDs(json: data)
        let base = (("~/Library/Developer/CoreSimulator/Devices") as NSString).expandingTildeInPath
        var total: Int64 = 0
        for udid in udids {
            total += try await directoryBytes("\(base)/\(udid)")
        }
        return total
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add DiskScanner and Shell helper"
```

---

### Task 5: `Cleaner` — async deletion

**Files:**
- Create: `XcodeCleaner/XcodeCleaner/Cleaner.swift`
- Test: add `CleanerTests.swift` under `XcodeCleanerTests/`

**Interfaces:**
- Consumes: `CleanupTarget`, `Shell`.
- Produces: `struct Cleaner { func clean(_ target: CleanupTarget) async -> Result<Void, Error>; func removeDirectoryContents(_ path: String) throws }`

- [ ] **Step 1: Write failing test** (`XcodeCleanerTests/CleanerTests.swift`)

```swift
import XCTest

final class CleanerTests: XCTestCase {
    func testRemoveDirectoryContentsLeavesDirEmpty() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)

        try Cleaner().removeDirectoryContents(dir.path)

        XCTAssertTrue(fm.fileExists(atPath: dir.path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path), [])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: FAIL — `Cleaner` undefined.

- [ ] **Step 3: Implement `Cleaner.swift`**

```swift
import Foundation

struct Cleaner {
    func clean(_ target: CleanupTarget) async -> Result<Void, Error> {
        do {
            switch target.kind {
            case .directory(let path):
                try removeDirectoryContents((path as NSString).expandingTildeInPath)
            case .unavailableSimulators:
                _ = try await Shell.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"])
            case .unusedRuntimes(let days):
                _ = try await Shell.run("/usr/bin/xcrun",
                    ["simctl", "runtime", "delete", "--notUsedSinceDays", String(days)])
            }
            return .success(())
        } catch { return .failure(error) }
    }

    /// Deletes everything inside `path` but keeps `path` itself.
    func removeDirectoryContents(_ path: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        for entry in try fm.contentsOfDirectory(atPath: path) {
            try fm.removeItem(atPath: (path as NSString).appendingPathComponent(entry))
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add Cleaner with directory-contents deletion"
```

---

### Task 6: `AppState` — target list + orchestration

**Files:**
- Create: `XcodeCleaner/XcodeCleaner/AppState.swift`

**Interfaces:**
- Consumes: `CleanupTarget`, `DiskScanner`, `Cleaner`.
- Produces:
  - `@MainActor @Observable final class AppState`
  - `let targets: [CleanupTarget]`
  - `func scanAll()`, `func scan(_ target: CleanupTarget)`, `func clean(_ target: CleanupTarget)`
  - `var totalText: String`

- [ ] **Step 1: Implement `AppState.swift`**

```swift
import Foundation

@MainActor
@Observable
final class AppState {
    let targets: [CleanupTarget]
    private let scanner = DiskScanner()
    private let cleaner = Cleaner()

    init() {
        targets = [
            CleanupTarget(name: "XcodeBuildMCP workspaces",
                          kind: .directory(path: "~/Library/Developer/XcodeBuildMCP/workspaces")),
            CleanupTarget(name: "Xcode DerivedData",
                          kind: .directory(path: "~/Library/Developer/Xcode/DerivedData")),
            CleanupTarget(name: "SwiftPM cache",
                          kind: .directory(path: "~/Library/Caches/org.swift.swiftpm")),
            CleanupTarget(name: "iOS DeviceSupport",
                          kind: .directory(path: "~/Library/Developer/Xcode/iOS DeviceSupport")),
            CleanupTarget(name: "Unused simulators", kind: .unavailableSimulators),
            CleanupTarget(name: "Unused simulator runtimes", kind: .unusedRuntimes(days: 30)),
        ]
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

- [ ] **Step 2: Build**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add AppState orchestrator"
```

---

### Task 7: `TargetRow` + `MenuBarView`

**Files:**
- Create: `XcodeCleaner/XcodeCleaner/TargetRow.swift`
- Create: `XcodeCleaner/XcodeCleaner/MenuBarView.swift`

**Interfaces:**
- Consumes: `AppState`, `CleanupTarget`, `TargetState`.
- Produces: `struct MenuBarView: View`, `struct TargetRow: View`.

- [ ] **Step 1: Implement `TargetRow.swift`**

```swift
import SwiftUI

struct TargetRow: View {
    let target: CleanupTarget
    let onClean: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name).font(.body)
                if case .error(let msg) = target.state {
                    Text(msg).font(.caption).foregroundStyle(.red).lineLimit(1)
                } else {
                    Text(target.sizeText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var trailing: some View {
        switch target.state {
        case .cleaning, .scanning:
            ProgressView().controlSize(.small)
        default:
            Button("Clean", action: onClean)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
```

- [ ] **Step 2: Implement `MenuBarView.swift`**

```swift
import SwiftUI

struct MenuBarView: View {
    @State private var state = AppState()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Xcode Cleaner").font(.headline)
                Spacer()
                Button { state.scanAll() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            Text("Reclaimable: \(state.totalText)")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            ForEach(state.targets) { target in
                TargetRow(target: target) { state.clean(target) }
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { state.scanAll() }
    }
}
```

- [ ] **Step 3: Build**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: add MenuBarView and TargetRow"
```

---

### Task 8: Wire app entry to `MenuBarView` + final verification

**Files:**
- Modify: `XcodeCleaner/XcodeCleaner/XcodeCleanerApp.swift`

**Interfaces:**
- Consumes: `MenuBarView`.

- [ ] **Step 1: Replace `XcodeCleanerApp.swift` body**

```swift
import SwiftUI

@main
struct XcodeCleanerApp: App {
    var body: some Scene {
        MenuBarExtra("Xcode Cleaner", systemImage: "trash") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 2: Build + run full app**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5 && open ~/Library/Developer/Xcode/DerivedData/XcodeCleaner-*/Build/Products/Debug/XcodeCleaner.app`
Expected: trash icon in menu bar; clicking shows the six rows; each populates with a size; "Reclaimable" total updates.

- [ ] **Step 3: Manual verification checklist**

  - Open the menu → rows show "scanning…" then real sizes.
  - Click **Clean** on SwiftPM cache → button becomes a spinner, then size drops.
  - Refresh button re-scans all rows.
  - `killall XcodeCleaner` when done.

- [ ] **Step 4: Run unit tests once more**

Run: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "feat: wire MenuBarView into app entry"
```

---

## Self-Review Notes

- **Spec coverage:** all six targets (Tasks 6); per-row Clean + spinner (Task 7); progress while cleaning (TargetState `.cleaning` → `ProgressView`); error inline (TargetRow); agent app + sandbox-off + trash icon (Task 1 Global Constraints); runtime "unused = 30 days" (Task 3/6). Covered.
- **Placeholder scan:** the only non-literal item is the full `project.pbxproj` body in Task 1 Step 5 (authored during execution against the stated structure) — unavoidable for a hand-rolled Xcode project; all Swift code is complete.
- **Type consistency:** `TargetState` cases, `CleanupKind` cases, `Shell.run`, `DiskScanner.size(of:)`, `Cleaner.clean(_:)`/`removeDirectoryContents(_:)`, and `AppState` API match across tasks.
