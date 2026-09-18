import XCTest
@testable import XcodeCleaner

final class TestClonesTests: XCTestCase {
    private var setDir: URL!

    override func setUpWithError() throws {
        setDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: setDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: setDir)
    }

    func testStaleTakesCloneUntouchedForDaysAndKeepsRecentOne() async throws {
        try makeCloneDir("OLD", modified: Self.daysAgo(3))
        try makeCloneDir("NEW", modified: Self.daysAgo(0))
        let runner = FakeCommandRunner(stdout: Self.json([
            ("OLD", true, "Shutdown"), ("NEW", true, "Shutdown")
        ]))

        let stale = try await TestClones.stale(days: 1, runner: runner, setPath: setDir.path)

        XCTAssertEqual(stale.map(\.udid), ["OLD"])
        XCTAssertEqual(runner.calls.map(\.args), [["simctl", "--set", setDir.path, "list", "devices", "-j"]])
    }

    /// An unavailable clone has lost its runtime and can never boot again, so
    /// it is garbage however recently it was written.
    func testStaleIncludesUnavailableCloneEvenWhenFresh() async throws {
        try makeCloneDir("GONE", modified: Self.daysAgo(0))
        let runner = FakeCommandRunner(stdout: Self.json([("GONE", false, "Shutdown")]))

        let stale = try await TestClones.stale(days: 30, runner: runner, setPath: setDir.path)

        XCTAssertEqual(stale.map(\.udid), ["GONE"])
    }

    /// A booted clone belongs to a test run in progress — never touch it.
    func testStaleSkipsBootedClone() async throws {
        try makeCloneDir("BUSY", modified: Self.daysAgo(90))
        let runner = FakeCommandRunner(stdout: Self.json([("BUSY", true, "Booted")]))

        let stale = try await TestClones.stale(days: 1, runner: runner, setPath: setDir.path)

        XCTAssertTrue(stale.isEmpty)
    }

    func testStaleSkipsSimctlEntirelyWhenSetDirectoryIsMissing() async throws {
        let runner = FakeCommandRunner(stdout: Self.json([("X", false, "Shutdown")]))

        let stale = try await TestClones.stale(
            days: 1, runner: runner, setPath: setDir.appendingPathComponent("nope").path
        )

        XCTAssertTrue(stale.isEmpty)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testStaleSurfacesNonZeroStatus() async {
        let runner = FakeCommandRunner(status: 2, stderr: Data("nope".utf8))
        do {
            _ = try await TestClones.stale(days: 1, runner: runner, setPath: setDir.path)
            XCTFail("expected failure on non-zero exit status")
        } catch {}
    }

    private func makeCloneDir(_ udid: String, modified: Date) throws {
        let dir = setDir.appendingPathComponent(udid)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: dir.path)
    }

    private static func daysAgo(_ days: Int) -> Date {
        Date().addingTimeInterval(-Double(days) * 86_400)
    }

    /// Shaped like `simctl --set <dir> list devices -j`, which reports no
    /// `lastBootedAt` for these clones — the fs stamp is the only age signal.
    private static func json(_ clones: [(udid: String, available: Bool, state: String)]) -> Data {
        let entries = clones.map { clone in
            """
            {
              "udid": "\(clone.udid)",
              "isAvailable": \(clone.available),
              \(clone.available ? "" : "\"availabilityError\": \"runtime profile not found\",")
              "state": "\(clone.state)",
              "name": "Clone 2 of iPhone 17 Pro"
            }
            """
        }
        return Data("""
        { "devices": { "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [\(entries.joined(separator: ","))] } }
        """.utf8)
    }
}
