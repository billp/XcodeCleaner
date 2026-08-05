import XCTest
@testable import XcodeCleaner

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

    func testRemoveDirectoryContentsToleratesEntryVanishingMidDelete() throws {
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
        try Cleaner().removeDirectoryContents(dir.path)

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

    func testCleanerPassesRuntimeDeleteArgs() async {
        let runner = FakeCommandRunner(status: 0)
        let cleaner = Cleaner(runner: runner)
        let target = CleanupTarget(name: "rt", kind: .unusedRuntimes(days: 30))
        _ = await cleaner.clean(target.kind)
        XCTAssertEqual(runner.calls.first?.args,
                       ["simctl", "runtime", "delete", "--notUsedSinceDays", "30"])
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
        // `simctl runtime delete --notUsedSinceDays N` exits 2 with this message
        // when nothing is old enough — that's "nothing to clean", not a failure.
        let runner = FakeCommandRunner(status: 2, stderr: Data("No matching images found to delete".utf8))
        let cleaner = Cleaner(runner: runner)
        let target = CleanupTarget(name: "rt", kind: .unusedRuntimes(days: 30))
        if case .failure = await cleaner.clean(target.kind) {
            XCTFail("‘no matching images’ should be treated as success")
        }
    }

    func testCleanRuntimesSurfacesRealError() async {
        let runner = FakeCommandRunner(status: 1, stderr: Data("some real failure".utf8))
        let cleaner = Cleaner(runner: runner)
        let target = CleanupTarget(name: "rt", kind: .unusedRuntimes(days: 30))
        if case .success = await cleaner.clean(target.kind) {
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
}
