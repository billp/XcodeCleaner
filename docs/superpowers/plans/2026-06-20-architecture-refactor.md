# XcodeCleaner Architecture Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the working XcodeCleaner app to MVVM + protocol-injected services with a grouped folder layout, plus SwiftLint/SwiftFormat config, a README, and ViewModel/service unit tests — without changing any behavior.

**Architecture:** Three service protocols (`CommandRunning`, `DiskScanning`, `Cleaning`) with the existing concrete impls and test fakes; `AppState` renamed to `CleanerViewModel` depending on the protocols via init with real defaults. Sources grouped into App/Models/Services/ViewModels/Views/Support folders.

**Tech Stack:** Swift 6, SwiftUI, macOS 14, Xcode file-system-synchronized groups, XCTest.

## Global Constraints

- Swift 6.0, macOS 14.0. App Sandbox disabled. Trash SF Symbol, `.menuBarExtraStyle(.window)`, `LSUIElement`.
- **Behavior-preserving:** no UI/feature/delete-semantics changes. All 8 existing tests must stay green; new tests are added.
- Subfolders inside the `XcodeCleaner/` synchronized group are auto-included — moving `.swift` files needs NO pbxproj edit. Only `Info.plist`/`XcodeCleaner.entitlements` moves require pbxproj path updates.
- Build: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6` → `** BUILD SUCCEEDED **`.
- Test: `cd ~/Projects/XcodeCleaner && xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10` → `** TEST SUCCEEDED **`.
- Parse noisy xcodebuild output by grepping for `BUILD SUCCEEDED`, `TEST SUCCEEDED`, `error:`.

---

## File Structure (target)

```
XcodeCleaner/
  App/        XcodeCleanerApp.swift
  Models/     CleanupTarget.swift, CleanupKind.swift, TargetState.swift
  Services/   CommandRunning.swift, DiskScanning.swift, Cleaning.swift, SimctlParsing.swift
  ViewModels/ CleanerViewModel.swift
  Views/      MenuBarView.swift, TargetRow.swift
  Support/    Info.plist, XcodeCleaner.entitlements
XcodeCleanerTests/
  SimctlParsingTests.swift, CleanerTests.swift, ShellTests.swift
  Fakes/ FakeCommandRunner.swift, FakeScanner.swift, FakeCleaner.swift
  CleanerViewModelTests.swift
.swiftlint.yml, .swiftformat, README.md
```

---

### Task 1: Folder reorg + move Info.plist/entitlements to Support/

**Files:**
- Move: all 8 `XcodeCleaner/*.swift` into subfolders (git mv, no content change)
- Move: `XcodeCleaner/Info.plist` → `XcodeCleaner/Support/Info.plist`; `XcodeCleaner/XcodeCleaner.entitlements` → `XcodeCleaner/Support/XcodeCleaner.entitlements`
- Modify: `XcodeCleaner.xcodeproj/project.pbxproj` (3 path references)

**Interfaces:**
- Produces: identical code in new locations. No symbol changes.

- [ ] **Step 1: Create folders and move source files (pure git mv)**

```bash
cd ~/Projects/XcodeCleaner/XcodeCleaner
mkdir -p App Models Services ViewModels Views Support
git mv XcodeCleanerApp.swift App/
git mv CleanupTarget.swift Models/
git mv SimctlParsing.swift Cleaner.swift DiskScanner.swift Services/
git mv AppState.swift ViewModels/
git mv MenuBarView.swift TargetRow.swift Views/
git mv Info.plist Support/
git mv XcodeCleaner.entitlements Support/
```

- [ ] **Step 2: Update the 3 pbxproj references**

Open `XcodeCleaner.xcodeproj/project.pbxproj`. Make exactly these replacements (they appear in build settings and the synchronized-group exception set):
- `INFOPLIST_FILE = XcodeCleaner/Info.plist;` → `INFOPLIST_FILE = XcodeCleaner/Support/Info.plist;` (Debug + Release configs)
- `CODE_SIGN_ENTITLEMENTS = XcodeCleaner/XcodeCleaner.entitlements;` → `CODE_SIGN_ENTITLEMENTS = XcodeCleaner/Support/XcodeCleaner.entitlements;` (Debug + Release configs)
- In the `PBXFileSystemSynchronizedBuildFileExceptionSet` `membershipExceptions` array, change the `Info.plist` entry to `Support/Info.plist` and `XcodeCleaner.entitlements` to `Support/XcodeCleaner.entitlements`.

Verify how many occurrences exist first:
```bash
cd ~/Projects/XcodeCleaner && grep -n "Info.plist\|XcodeCleaner.entitlements" XcodeCleaner.xcodeproj/project.pbxproj
```
Edit each occurrence to the `Support/...` path. (The `INFOPLIST_FILE`/`CODE_SIGN_ENTITLEMENTS` settings typically appear twice each — Debug and Release; the exception set entries once each.)

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`. If it fails with "Info.plist not found" or a signing/entitlements path error, re-check that every occurrence from the grep now points at `Support/`.

- [ ] **Step 4: Test**

Run the test command. Expected: `** TEST SUCCEEDED **` (still 8 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "refactor: group sources into folders; move Info.plist/entitlements to Support"
```

---

### Task 2: Split CleanupTarget into three Model files

**Files:**
- Modify: `XcodeCleaner/Models/CleanupTarget.swift` (remove the two enums)
- Create: `XcodeCleaner/Models/CleanupKind.swift`, `XcodeCleaner/Models/TargetState.swift`

**Interfaces:**
- Produces: `CleanupKind`, `TargetState`, `CleanupTarget` unchanged in API — only split across files.

- [ ] **Step 1: Create `Models/CleanupKind.swift`**

```swift
import Foundation

enum CleanupKind: Equatable {
    case directory(path: String)
    case unavailableSimulators
    case unusedRuntimes(days: Int)
}
```

- [ ] **Step 2: Create `Models/TargetState.swift`**

```swift
import Foundation

enum TargetState: Equatable {
    case idle
    case scanning
    case scanned(Int64)
    case cleaning
    case cleaned(Int64)
    case error(String)
}
```

- [ ] **Step 3: Trim `Models/CleanupTarget.swift`** so it contains only the class (delete the two enum declarations now living in their own files; keep the rest verbatim):

```swift
import Foundation

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

- [ ] **Step 4: Build + Test** — both commands. Expected `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **` (8 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "refactor: split CleanupKind and TargetState into own files"
```

---

### Task 3: `CommandRunning` protocol + `Shell` struct + inject runner

**Files:**
- Create: `XcodeCleaner/Services/CommandRunning.swift` (protocol + `ScanError` + `Shell`)
- Modify: `XcodeCleaner/Services/DiskScanner.swift` (remove Shell/ScanError; add `runner`)
- Modify: `XcodeCleaner/Services/Cleaner.swift` (use `runner`)
- Modify: `XcodeCleanerTests/ShellTests.swift` (instance call)

**Interfaces:**
- Produces:
  - `protocol CommandRunning: Sendable { func run(_ launchPath: String, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data) }`
  - `enum ScanError: Error, Equatable { case process(String) }`
  - `struct Shell: CommandRunning`
  - `struct DiskScanner` now has `init(runner: CommandRunning = Shell())`
  - `struct Cleaner` now has `init(runner: CommandRunning = Shell())`

- [ ] **Step 1: Create `Services/CommandRunning.swift`** (move `ScanError` + the existing `Shell.run` body here, converting `enum Shell`/`static func` to `struct Shell: CommandRunning`/instance `func`)

```swift
import Foundation

enum ScanError: Error, Equatable { case process(String) }

protocol CommandRunning: Sendable {
    func run(_ launchPath: String, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data)
}

struct Shell: CommandRunning {
    func run(_ launchPath: String, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: launchPath)
            p.arguments = args
            let out = Pipe()
            let err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.terminationHandler = { proc in
                let outData = (try? out.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? err.fileHandleForReading.readToEnd()) ?? Data()
                cont.resume(returning: (proc.terminationStatus, outData, errData))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}
```

Note: if the current `Shell.run` body differs (e.g. helper names), preserve its exact current logic — only change the type declaration (`enum`→`struct: CommandRunning`) and `static func run`→`func run`, and move `ScanError` here. Remove `ScanError` and `Shell` from `DiskScanner.swift`.

- [ ] **Step 2: Update `Services/DiskScanner.swift`** to store and use a runner. Add the stored property + init at the top of the struct and replace every `Shell.run(` / `try await Shell.run(` call with `runner.run(`:

```swift
struct DiskScanner {
    let runner: CommandRunning

    init(runner: CommandRunning = Shell()) {
        self.runner = runner
    }

    // ... existing size(of:) and private helpers unchanged,
    // except each `try await Shell.run(...)` becomes `try await runner.run(...)`
}
```

- [ ] **Step 3: Update `Services/Cleaner.swift`** the same way:

```swift
struct Cleaner {
    let runner: CommandRunning

    init(runner: CommandRunning = Shell()) {
        self.runner = runner
    }

    // ... existing clean(_:) and removeDirectoryContents(_:) unchanged,
    // except each `try await Shell.run(...)` becomes `try await runner.run(...)`
}
```

- [ ] **Step 4: Update `XcodeCleanerTests/ShellTests.swift`** — `Shell` is now a struct with an instance method. Replace `Shell.run(` with `Shell().run(`:

```swift
func testShellRunCapturesNonZeroStatusAndStderr() async throws {
    let result = try await Shell().run("/bin/sh", ["-c", "echo boom 1>&2; exit 3"])
    XCTAssertEqual(result.status, 3)
    XCTAssertTrue(String(data: result.stderr, encoding: .utf8)!.contains("boom"))
}

func testShellRunCapturesStdout() async throws {
    let result = try await Shell().run("/bin/echo", ["hello"])
    XCTAssertEqual(result.status, 0)
    XCTAssertTrue(String(data: result.stdout, encoding: .utf8)!.contains("hello"))
}
```

(Keep the existing `import XCTest` / `@testable import XcodeCleaner` header. If the current test method names/bodies differ, change only `Shell.run` → `Shell().run`.)

- [ ] **Step 5: Build + Test** — Expected `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **` (8 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "refactor: extract CommandRunning protocol; inject runner into services"
```

---

### Task 4: `DiskScanning` + `Cleaning` protocols

**Files:**
- Rename + modify: `XcodeCleaner/Services/DiskScanner.swift` → `XcodeCleaner/Services/DiskScanning.swift` (add protocol + conformance)
- Rename + modify: `XcodeCleaner/Services/Cleaner.swift` → `XcodeCleaner/Services/Cleaning.swift` (add protocol + conformance)

**Interfaces:**
- Produces:
  - `protocol DiskScanning: Sendable { func size(of target: CleanupTarget) async -> Result<Int64, Error> }` with `struct DiskScanner: DiskScanning`
  - `protocol Cleaning: Sendable { func clean(_ target: CleanupTarget) async -> Result<Void, Error> }` with `struct Cleaner: Cleaning`

- [ ] **Step 1: Rename the files**

```bash
cd ~/Projects/XcodeCleaner/XcodeCleaner/Services
git mv DiskScanner.swift DiskScanning.swift
git mv Cleaner.swift Cleaning.swift
```

- [ ] **Step 2: Add the `DiskScanning` protocol and conformance** at the top of `Services/DiskScanning.swift`:

```swift
protocol DiskScanning: Sendable {
    func size(of target: CleanupTarget) async -> Result<Int64, Error>
}
```

and change the struct declaration to `struct DiskScanner: DiskScanning {` (its `size(of:)` already matches the requirement).

- [ ] **Step 3: Add the `Cleaning` protocol and conformance** at the top of `Services/Cleaning.swift`:

```swift
protocol Cleaning: Sendable {
    func clean(_ target: CleanupTarget) async -> Result<Void, Error>
}
```

and change the struct declaration to `struct Cleaner: Cleaning {` (its `clean(_:)` already matches).

- [ ] **Step 4: Build + Test** — Expected `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **` (8 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "refactor: add DiskScanning and Cleaning protocols"
```

---

### Task 5: Rename `AppState` → `CleanerViewModel` with protocol-typed init

**Files:**
- Rename + modify: `XcodeCleaner/ViewModels/AppState.swift` → `XcodeCleaner/ViewModels/CleanerViewModel.swift`
- Modify: `XcodeCleaner/Views/MenuBarView.swift`

**Interfaces:**
- Consumes: `DiskScanning`, `Cleaning`.
- Produces: `@MainActor @Observable final class CleanerViewModel` with `init(scanner: DiskScanning = DiskScanner(), cleaner: Cleaning = Cleaner())`, and unchanged `targets`, `scanAll()`, `scan(_:)`, `clean(_:)`, `totalText`.

- [ ] **Step 1: Rename the file**

```bash
cd ~/Projects/XcodeCleaner/XcodeCleaner/ViewModels && git mv AppState.swift CleanerViewModel.swift
```

- [ ] **Step 2: Rewrite `ViewModels/CleanerViewModel.swift`** — rename the class and change the stored deps to protocol types with defaulted init (body otherwise identical to the current `AppState`):

```swift
import Foundation

@MainActor
@Observable
final class CleanerViewModel {
    let targets: [CleanupTarget]
    private let scanner: DiskScanning
    private let cleaner: Cleaning

    init(scanner: DiskScanning = DiskScanner(), cleaner: Cleaning = Cleaner()) {
        self.scanner = scanner
        self.cleaner = cleaner
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

(If the current `AppState` body differs from the above, preserve its logic — change only the class name, the two stored-property types to `DiskScanning`/`Cleaning`, and the `init` signature.)

- [ ] **Step 3: Update `Views/MenuBarView.swift`** — replace the state type/name. Change `@State private var state = AppState()` to `@State private var vm = CleanerViewModel()` and every `state.` to `vm.`:

```swift
import SwiftUI

struct MenuBarView: View {
    @State private var vm = CleanerViewModel()

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
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { vm.scanAll() }
    }
}
```

(If the current `MenuBarView` markup differs, keep it and change only the `@State` declaration and the `state.` → `vm.` references. `TargetRow` does not reference `AppState` and needs no change.)

- [ ] **Step 4: Build + Test** — Expected `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **` (8 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "refactor: rename AppState to CleanerViewModel with protocol DI"
```

---

### Task 6: Fakes + service and ViewModel tests

**Files:**
- Create: `XcodeCleanerTests/Fakes/FakeCommandRunner.swift`, `XcodeCleanerTests/Fakes/FakeScanner.swift`, `XcodeCleanerTests/Fakes/FakeCleaner.swift`
- Create: `XcodeCleanerTests/CleanerViewModelTests.swift`
- Modify: `XcodeCleanerTests/CleanerTests.swift` (add the runner-based service tests) — or add a new `ServiceDispatchTests.swift`

**Interfaces:**
- Consumes: `CommandRunning`, `DiskScanning`, `Cleaning`, `DiskScanner`, `Cleaner`, `CleanerViewModel`, `CleanupTarget`, `ScanError`.

- [ ] **Step 1: Create `Fakes/FakeCommandRunner.swift`**

```swift
import Foundation
@testable import XcodeCleaner

final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    struct Response { let status: Int32; let stdout: Data; let stderr: Data }

    private let lock = NSLock()
    private var responses: [Response]
    private(set) var calls: [(launchPath: String, args: [String])] = []

    init(responses: [Response]) { self.responses = responses }

    convenience init(status: Int32 = 0, stdout: Data = Data(), stderr: Data = Data()) {
        self.init(responses: [Response(status: status, stdout: stdout, stderr: stderr)])
    }

    func run(_ launchPath: String, _ args: [String]) async throws
        -> (status: Int32, stdout: Data, stderr: Data) {
        lock.lock(); defer { lock.unlock() }
        calls.append((launchPath, args))
        let r = responses.count > 1 ? responses.removeFirst()
            : (responses.first ?? Response(status: 0, stdout: Data(), stderr: Data()))
        return (r.status, r.stdout, r.stderr)
    }
}
```

- [ ] **Step 2: Create `Fakes/FakeScanner.swift`**

```swift
import Foundation
@testable import XcodeCleaner

final class FakeScanner: DiskScanning, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<Int64, Error>
    private(set) var scannedNames: [String] = []

    init(result: Result<Int64, Error>) { self.result = result }

    func size(of target: CleanupTarget) async -> Result<Int64, Error> {
        lock.lock(); scannedNames.append(target.name); lock.unlock()
        return result
    }
}
```

- [ ] **Step 3: Create `Fakes/FakeCleaner.swift`**

```swift
import Foundation
@testable import XcodeCleaner

final class FakeCleaner: Cleaning, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<Void, Error>
    private(set) var cleanedNames: [String] = []

    init(result: Result<Void, Error>) { self.result = result }

    func clean(_ target: CleanupTarget) async -> Result<Void, Error> {
        lock.lock(); cleanedNames.append(target.name); lock.unlock()
        return result
    }
}
```

- [ ] **Step 4: Add service dispatch tests.** Append to `XcodeCleanerTests/CleanerTests.swift` (inside the existing `final class CleanerTests`):

```swift
func testCleanerSurfacesNonZeroStatusForSimulators() async {
    let runner = FakeCommandRunner(status: 2, stderr: Data("nope".utf8))
    let cleaner = Cleaner(runner: runner)
    let target = CleanupTarget(name: "sim", kind: .unavailableSimulators)
    if case .success = await cleaner.clean(target) {
        XCTFail("expected failure on non-zero exit status")
    }
}

func testCleanerPassesRuntimeDeleteArgs() async {
    let runner = FakeCommandRunner(status: 0)
    let cleaner = Cleaner(runner: runner)
    let target = CleanupTarget(name: "rt", kind: .unusedRuntimes(days: 30))
    _ = await cleaner.clean(target)
    XCTAssertEqual(runner.calls.first?.args,
                   ["simctl", "runtime", "delete", "--notUsedSinceDays", "30"])
}

func testScannerSurfacesNonZeroStatusForRuntimes() async {
    let runner = FakeCommandRunner(status: 1, stderr: Data("boom".utf8))
    let scanner = DiskScanner(runner: runner)
    let target = CleanupTarget(name: "rt", kind: .unusedRuntimes(days: 30))
    if case .success = await scanner.size(of: target) {
        XCTFail("expected failure on non-zero exit status")
    }
}
```

- [ ] **Step 5: Create `CleanerViewModelTests.swift`**

```swift
import XCTest
@testable import XcodeCleaner

@MainActor
final class CleanerViewModelTests: XCTestCase {
    /// Polls until `cond` is true or the timeout elapses (ViewModel mutates state from an async Task).
    private func waitUntil(timeout: TimeInterval = 2.0, _ cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testScanSetsScannedBytes() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(123)),
                                  cleaner: FakeCleaner(result: .success(())))
        let target = vm.targets[0]
        vm.scan(target)
        await waitUntil { if case .scanned = target.state { return true }; return false }
        XCTAssertEqual(target.sizeBytes, 123)
    }

    func testScanFailureSetsError() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .failure(ScanError.process("x"))),
                                  cleaner: FakeCleaner(result: .success(())))
        let target = vm.targets[0]
        vm.scan(target)
        await waitUntil { if case .error = target.state { return true }; return false }
        if case .error = target.state {} else { XCTFail("expected .error state") }
    }

    func testCleanSetsCleanedBytes() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .success(())))
        let target = vm.targets[0]
        vm.clean(target)
        await waitUntil { if case .cleaned = target.state { return true }; return false }
        XCTAssertEqual(target.sizeBytes, 0)
    }

    func testCleanFailureSetsError() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .failure(ScanError.process("y"))))
        let target = vm.targets[0]
        vm.clean(target)
        await waitUntil { if case .error = target.state { return true }; return false }
        if case .error = target.state {} else { XCTFail("expected .error state") }
    }
}
```

- [ ] **Step 6: Build + Test** — Expected `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`. Confirm the new tests ran: grep the test output for `CleanerViewModelTests` and the new `CleanerTests` method names. Total should be 15 tests (8 existing + 3 service + 4 ViewModel).

- [ ] **Step 7: Commit**

```bash
cd ~/Projects/XcodeCleaner && git add -A && git commit -m "test: add fakes and ViewModel/service dispatch tests"
```

---

### Task 7: SwiftLint + SwiftFormat config + README

**Files:**
- Create: `.swiftlint.yml`, `.swiftformat`, `README.md` (repo root)

**Interfaces:** none (config + docs only; no build impact).

- [ ] **Step 1: Create `.swiftlint.yml`**

```yaml
# SwiftLint config for XcodeCleaner. Install: `brew install swiftlint`; run: `swiftlint`.
included:
  - XcodeCleaner
  - XcodeCleanerTests
disabled_rules:
  - todo
opt_in_rules:
  - empty_count
  - closure_spacing
  - force_unwrapping
line_length:
  warning: 120
  error: 160
force_unwrapping:
  severity: warning
identifier_name:
  min_length: 1
```

- [ ] **Step 2: Create `.swiftformat`**

```
--swiftversion 6.0
--indent 4
--maxwidth 120
--wraparguments before-first
--wrapcollections before-first
--commas inline
--self remove
--exclude .build
```

- [ ] **Step 3: Create `README.md`**

```markdown
# Xcode Cleaner

A macOS menu bar app that shows the disk usage of Xcode-related caches and lets you reclaim space per-target. A trash icon sits in the menu bar; clicking it lists each cache with its current size and an individual **Clean** button that shows live progress.

## Targets cleaned

| Row | What it removes |
|-----|-----------------|
| XcodeBuildMCP workspaces | `~/Library/Developer/XcodeBuildMCP/workspaces` contents |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` contents |
| SwiftPM cache | `~/Library/Caches/org.swift.swiftpm` contents |
| iOS DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport` contents |
| Unused simulators | `xcrun simctl delete unavailable` |
| Unused simulator runtimes | `xcrun simctl runtime delete --notUsedSinceDays 30` |

> Clean buttons delete immediately — there is no confirmation dialog.

## Architecture

MVVM with protocol-injected services:

- **Models** (`CleanupTarget`, `CleanupKind`, `TargetState`) — what to clean and per-row state.
- **Services** — `CommandRunning` (`Shell`) runs processes; `DiskScanning` (`DiskScanner`) computes sizes; `Cleaning` (`Cleaner`) deletes; `SimctlParsing` parses `simctl` JSON. Each service is a protocol with a concrete impl and a test fake.
- **ViewModel** (`CleanerViewModel`) — `@MainActor @Observable`; owns the targets and orchestrates scan/clean. Depends on the service protocols (real defaults), so it is unit-tested with fakes.
- **Views** (`MenuBarView`, `TargetRow`) — the menu bar dropdown.

The app is an agent (`LSUIElement`, no Dock icon) with the App Sandbox disabled (it needs access to `~/Library/Developer` and `xcrun`).

## Build / run / test

```bash
# Build
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner build CODE_SIGNING_ALLOWED=NO

# Test
xcodebuild -project XcodeCleaner.xcodeproj -scheme XcodeCleaner test CODE_SIGNING_ALLOWED=NO

# Run the built app
open ~/Library/Developer/Xcode/DerivedData/XcodeCleaner-*/Build/Products/Debug/XcodeCleaner.app
```

Requirements: macOS 14+, Xcode 16+ (developed on Xcode 26.3 / Swift 6.2).
```

- [ ] **Step 4: Build** (sanity — config/docs don't affect the build). Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit** (these files are not under the globally-ignored `docs/superpowers`, but verify they were added):

```bash
cd ~/Projects/XcodeCleaner && git add -A && git status --porcelain && git commit -m "chore: add SwiftLint/SwiftFormat config and README"
```

---

## Self-Review Notes

- **Spec coverage:** folder grouping (Task 1), model split (Task 2), `CommandRunning`+DI (Task 3), `DiskScanning`/`Cleaning` (Task 4), `CleanerViewModel` rename + protocol init (Task 5), fakes + ViewModel/service tests (Task 6), SwiftLint/SwiftFormat/README (Task 7). All spec sections covered.
- **Behavior preservation:** every task ends with the full build + 8-test (then 15-test) suite green.
- **Placeholder scan:** the "if the current X differs, preserve its logic" notes refer to verbatim-existing code the implementer can read in the repo — not placeholders; full target code is given for every file.
- **Type consistency:** `CommandRunning.run` returns the 3-tuple used by `DiskScanner`/`Cleaner`; `DiskScanning.size(of:)`/`Cleaning.clean(_:)` match `CleanerViewModel`'s usage and the fakes; `ScanError.process` used consistently.
