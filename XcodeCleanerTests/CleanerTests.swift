import XCTest
import os
@testable import XcodeCleaner

final class CleanerTests: XCTestCase {
    func testRemoveDirectoryContentsLeavesDirEmpty() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)

        try await Cleaner().removeDirectoryContents(dir.path)

        XCTAssertTrue(fm.fileExists(atPath: dir.path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path), [])
    }

    func testRemoveDirectoryContentsToleratesEntryVanishingMidDelete() async throws {
        // Simulates a concurrent writer (e.g. an active build churning
        // ModuleCache.noindex): an entry disappears after enumeration but before
        // removal. The clean should still empty the directory without throwing.
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // A deep tree whose leaves we delete out from under the cleaner.
        let nested = dir.appendingPathComponent("ModuleCache.noindex/inner")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        for i in 0..<20 {
            try "x".write(to: nested.appendingPathComponent("\(i).tmp"), atomically: true, encoding: .utf8)
        }
        try "y".write(to: dir.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)

        // Race: delete the nested tree concurrently while the cleaner runs.
        let racer = Thread { try? fm.removeItem(at: nested) }
        racer.start()
        try await Cleaner().removeDirectoryContents(dir.path)

        XCTAssertTrue(fm.fileExists(atPath: dir.path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path), [])
    }

    func testCleanerSurfacesNonZeroStatusForSimulators() async {
        let runner = FakeCommandRunner(status: 2, stderr: Data("nope".utf8))
        let cleaner = Cleaner(runner: runner)
        let target = CleanupTarget(name: "sim", kind: .unavailableSimulators)
        if case .success = await cleaner.clean(target.kind) {
            XCTFail("expected failure on non-zero exit status")
        }
    }

    /// The runtime clean resolves identifiers itself rather than delegating to
    /// `--notUsedSinceDays`, which ignores never-used runtimes. "B" here is a
    /// downloaded-but-never-booted runtime — exactly the case the flag misses.
    func testCleanerDeletesEachUnusedRuntimeByIdentifier() async {
        let list = """
        {
          "A": { "identifier": "A", "sizeBytes": 100, "lastUsedAt": "\(Self.iso(daysAgo: 1))" },
          "B": { "identifier": "B", "sizeBytes": 200 },
          "C": { "identifier": "C", "sizeBytes": 300, "lastUsedAt": "\(Self.iso(daysAgo: 90))" }
        }
        """
        let runner = FakeCommandRunner(responses: [
            .init(status: 0, stdout: Data(list.utf8), stderr: Data()),
            .init(status: 0, stdout: Data(), stderr: Data()),
            .init(status: 0, stdout: Data(), stderr: Data()),
            .init(status: 0, stdout: Data("{}".utf8), stderr: Data())
        ])
        let result = await Self.fastCleaner(runner).clean(.unusedRuntimes(days: 30))
        if case .failure = result { XCTFail("expected success") }
        XCTAssertEqual(runner.calls.map(\.args), [
            ["simctl", "runtime", "list", "-j"],
            ["simctl", "runtime", "delete", "B"],
            ["simctl", "runtime", "delete", "C"],
            ["simctl", "runtime", "list", "-j"]   // settle check
        ])
    }

    /// `simctl runtime delete` returns before the mobile asset is actually
    /// purged, so the runtime keeps showing up (at full size) in `runtime list`
    /// for a moment. The clean must not return while that's still the case, or
    /// the caller re-scans and the row shows the size it just freed.
    func testCleanRuntimesWaitsUntilSimctlStopsListingTheDeletedRuntime() async {
        let stillThere = """
        { "A": { "identifier": "A", "sizeBytes": 8000000000 } }
        """
        let runner = FakeCommandRunner(responses: [
            .init(status: 0, stdout: Data(stillThere.utf8), stderr: Data()),  // list
            .init(status: 0, stdout: Data(), stderr: Data()),                 // delete A
            .init(status: 0, stdout: Data(stillThere.utf8), stderr: Data()),  // still listed
            .init(status: 0, stdout: Data("{}".utf8), stderr: Data())         // now gone
        ])
        let result = await Self.fastCleaner(runner).clean(.unusedRuntimes(days: 30))
        if case .failure = result { XCTFail("expected success") }
        XCTAssertEqual(runner.calls.count, 4, "should poll until the runtime is gone")
    }

    func testCleanRuntimesGivesUpWaitingRatherThanHanging() async {
        // The runtime never disappears from the list. The delete itself worked,
        // so this stays a success — the wait is best-effort.
        let stuck = """
        { "A": { "identifier": "A", "sizeBytes": 8000000000 } }
        """
        let runner = FakeCommandRunner(status: 0, stdout: Data(stuck.utf8))
        let cleaner = Cleaner(runner: runner,
                              runtimeSettleTimeout: .milliseconds(60),
                              runtimeSettlePoll: .milliseconds(10))
        if case .failure = await cleaner.clean(.unusedRuntimes(days: 30)) {
            XCTFail("a delete that worked shouldn't fail just because the list lags")
        }
    }

    private static func fastCleaner(_ runner: CommandRunning) -> Cleaner {
        Cleaner(runner: runner, runtimeSettleTimeout: .seconds(2), runtimeSettlePoll: .milliseconds(5))
    }

    func testCleanRuntimesDoesNothingWhenNoneAreUnused() async {
        let list = """
        { "A": { "identifier": "A", "sizeBytes": 100, "lastUsedAt": "\(Self.iso(daysAgo: 1))" } }
        """
        let runner = FakeCommandRunner(status: 0, stdout: Data(list.utf8))
        let result = await Cleaner(runner: runner).clean(.unusedRuntimes(days: 30))
        if case .failure = result { XCTFail("expected success") }
        XCTAssertEqual(runner.calls.count, 1, "only the list call should run")
    }

    func testCleanRuntimesSurfacesListFailure() async {
        let runner = FakeCommandRunner(status: 1, stderr: Data("boom".utf8))
        if case .success = await Cleaner(runner: runner).clean(.unusedRuntimes(days: 30)) {
            XCTFail("a failing runtime list should surface as failure")
        }
    }

    private static func iso(daysAgo: Int) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(daysAgo) * 86_400))
    }

    func testScannerSurfacesNonZeroStatusForRuntimes() async {
        let runner = FakeCommandRunner(status: 1, stderr: Data("boom".utf8))
        let scanner = DiskScanner(runner: runner)
        let target = CleanupTarget(name: "rt", kind: .unusedRuntimes(days: 30))
        if case .success = await scanner.size(of: target.kind) {
            XCTFail("expected failure on non-zero exit status")
        }
    }

    func testCleanRuntimesTreatsNoMatchingAsSuccess() async {
        // `simctl runtime delete <id>` exits 2 with this message when the runtime
        // is already gone — that's "nothing to clean", not a failure.
        let list = """
        { "A": { "identifier": "A", "sizeBytes": 100 } }
        """
        let runner = FakeCommandRunner(responses: [
            .init(status: 0, stdout: Data(list.utf8), stderr: Data()),
            .init(status: 2, stdout: Data(), stderr: Data("No matching images found to delete".utf8)),
            .init(status: 0, stdout: Data("{}".utf8), stderr: Data())
        ])
        if case .failure = await Self.fastCleaner(runner).clean(.unusedRuntimes(days: 30)) {
            XCTFail("‘no matching images’ should be treated as success")
        }
    }

    func testCleanRuntimesSurfacesRealError() async {
        let list = """
        { "A": { "identifier": "A", "sizeBytes": 100 } }
        """
        let runner = FakeCommandRunner(responses: [
            .init(status: 0, stdout: Data(list.utf8), stderr: Data()),
            .init(status: 1, stdout: Data(), stderr: Data("some real failure".utf8))
        ])
        if case .success = await Cleaner(runner: runner).clean(.unusedRuntimes(days: 30)) {
            XCTFail("a real error should surface as failure")
        }
    }

    func testProcessErrorShowsMessageInLocalizedDescription() {
        XCTAssertEqual(ProcessError.process("boom").localizedDescription, "boom")
    }

    // MARK: - .build folders

    func testBuildFoldersScannerSumsEveryFoundDirectory() async throws {
        // find enumerates two real .build dirs; du reports 10 KB and 15 KB.
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = base.appendingPathComponent("ProjA/.build")
        let b = base.appendingPathComponent("ProjB/.build")
        try fm.createDirectory(at: a, withIntermediateDirectories: true)
        try fm.createDirectory(at: b, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let runner = FakeCommandRunner(responses: [
            .init(status: 0, stdout: Data("\(a.path)\u{0}\(b.path)\u{0}".utf8), stderr: Data()),
            .init(status: 0, stdout: Data("10\t\(a.path)".utf8), stderr: Data()),
            .init(status: 0, stdout: Data("15\t\(b.path)".utf8), stderr: Data())
        ])
        let result = await DiskScanner(runner: runner).size(of: .buildFolders(root: base.path))
        guard case .success(let bytes) = result else { return XCTFail("expected success") }
        XCTAssertEqual(bytes, (10 + 15) * 1024)
    }

    func testCleanBuildFoldersRemovesBuildDirButKeepsSiblings() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let build = base.appendingPathComponent("ProjA/.build")
        let sources = base.appendingPathComponent("ProjA/Sources")
        try fm.createDirectory(at: build, withIntermediateDirectories: true)
        try fm.createDirectory(at: sources, withIntermediateDirectories: true)
        try "x".write(to: build.appendingPathComponent("f.o"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: base) }

        // find is called twice: enumerate, then verify none remain.
        let runner = FakeCommandRunner(responses: [
            .init(status: 0, stdout: Data("\(build.path)\u{0}".utf8), stderr: Data()),
            .init(status: 0, stdout: Data(), stderr: Data())
        ])
        let result = await Cleaner(runner: runner).clean(.buildFolders(root: base.path))
        if case .failure = result { XCTFail("expected success") }
        XCTAssertFalse(fm.fileExists(atPath: build.path), ".build should be removed entirely")
        XCTAssertTrue(fm.fileExists(atPath: sources.path), "sibling Sources must be untouched")
    }

    func testBuildFoldersScannerReturnsZeroWhenRootMissing() async {
        let runner = FakeCommandRunner(status: 0)
        let missing = "/tmp/\(UUID().uuidString)/does-not-exist"
        let result = await DiskScanner(runner: runner).size(of: .buildFolders(root: missing))
        guard case .success(let bytes) = result else { return XCTFail("expected success") }
        XCTAssertEqual(bytes, 0)
        XCTAssertTrue(runner.calls.isEmpty, "a missing root should short-circuit before running find")
    }

    func testBuildFolderScanPrunesLibrarySubtree() async throws {
        // The scan must prune <root>/Library so it never walks into other apps'
        // sandboxed containers, which trips macOS's "access data from other
        // apps" privacy prompt.
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let runner = FakeCommandRunner(status: 0, stdout: Data())
        _ = try await BuildFolders.paths(root: root.path, runner: runner)

        let call = runner.calls.first
        XCTAssertEqual(call?.launchPath, "/usr/bin/find")
        XCTAssertEqual(call?.args.first, root.path)
        XCTAssertTrue(
            call?.args.contains("\(root.path)/Library") ?? false,
            "scan must prune the Library subtree"
        )
    }

    func testRemoveDirectoryContentsSparesEntriesInUse() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        let busy = dir.appendingPathComponent("wt-busy/DerivedData")
        let idle = dir.appendingPathComponent("wt-idle/DerivedData")
        try fm.createDirectory(at: busy, withIntermediateDirectories: true)
        try fm.createDirectory(at: idle, withIntermediateDirectories: true)

        try await Cleaner().removeDirectoryContents(dir.path, sparing: { [PathsInUse.normalize(busy.path)] })

        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path), ["wt-busy"])
        XCTAssertTrue(fm.fileExists(atPath: busy.path))
    }

    /// Deleting a big target takes minutes; a build that starts partway through
    /// must keep its folder, so what's in use is re-checked for every entry.
    func testRemoveDirectoryContentsSparesABuildThatStartsMidClean() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        let names = (0..<6).map { "wt-\($0)" }
        for name in names {
            try fm.createDirectory(at: dir.appendingPathComponent("\(name)/DerivedData"),
                                   withIntermediateDirectories: true)
        }
        // Nothing builds at first; once the clean is underway, every remaining
        // folder is in use (as if builds started in all of them).
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let allFolders = Set(names.map { PathsInUse.normalize(dir.appendingPathComponent("\($0)/DerivedData").path) })
        let provider: PathsInUseProvider = {
            calls.withLock { $0 += 1; return $0 } > 1 ? allFolders : []
        }

        try await Cleaner().removeDirectoryContents(dir.path, sparing: provider)

        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path).count, names.count - 1,
                       "only the entry checked before any build started may go")
    }

    func testCleanBuildFoldersSparesOneInUse() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: base) }
        let busy = base.appendingPathComponent("Building/.build")
        let idle = base.appendingPathComponent("Idle/.build")
        try fm.createDirectory(at: busy, withIntermediateDirectories: true)
        try fm.createDirectory(at: idle, withIntermediateDirectories: true)

        let found = Data("\(busy.path)\u{0}\(idle.path)\u{0}".utf8)
        let runner = FakeCommandRunner(responses: [
            .init(status: 0, stdout: found, stderr: Data()),
            .init(status: 0, stdout: Data("\(busy.path)\u{0}".utf8), stderr: Data()),
        ])
        let inUse: Set<String> = [PathsInUse.normalize(busy.path)]
        let result = await Cleaner(runner: runner).clean(.buildFolders(root: base.path), sparing: { inUse })

        if case .failure(let error) = result { XCTFail("expected success, got \(error)") }
        XCTAssertTrue(fm.fileExists(atPath: busy.path), ".build in use must stay")
        XCTAssertFalse(fm.fileExists(atPath: idle.path))
    }
}
