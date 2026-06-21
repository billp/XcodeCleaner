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

    func testScanErrorShowsMessageInLocalizedDescription() {
        XCTAssertEqual(ScanError.process("boom").localizedDescription, "boom")
    }
}
