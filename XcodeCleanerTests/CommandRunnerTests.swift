import XCTest
@testable import XcodeCleaner

final class CommandRunnerTests: XCTestCase {
    func testShellRunCapturesNonZeroStatusAndStderr() async throws {
        let (status, _, stderr) = try await CommandRunner().run("/bin/sh", ["-c", "echo boom 1>&2; exit 3"])
        XCTAssertEqual(status, 3)
        let text = String(data: stderr, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("boom"), "Expected 'boom' in stderr, got: \(text)")
    }

    func testShellRunCapturesStdout() async throws {
        let (status, stdout, _) = try await CommandRunner().run("/bin/echo", ["hello"])
        XCTAssertEqual(status, 0)
        let text = String(data: stdout, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("hello"), "Expected 'hello' in stdout, got: \(text)")
    }

    /// Regression: output larger than the OS pipe buffer (~64KB) must not deadlock.
    /// The old Pipe-based implementation hung here because the child blocked on a
    /// full stdout buffer and never exited (so terminationHandler never fired).
    func testShellRunHandlesOutputLargerThanPipeBuffer() async throws {
        // ~220KB of stdout (20000 lines × 11 bytes), well over the 64KB buffer.
        let (status, stdout, _) = try await CommandRunner().run("/bin/sh", ["-c", "yes 1234567890 | head -n 20000"])
        XCTAssertEqual(status, 0)
        XCTAssertGreaterThan(stdout.count, 100_000)
    }
}
