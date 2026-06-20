import XCTest
@testable import XcodeCleaner

final class ShellTests: XCTestCase {
    func testShellRunCapturesNonZeroStatusAndStderr() async throws {
        let (status, _, stderr) = try await Shell().run("/bin/sh", ["-c", "echo boom 1>&2; exit 3"])
        XCTAssertEqual(status, 3)
        let text = String(data: stderr, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("boom"), "Expected 'boom' in stderr, got: \(text)")
    }

    func testShellRunCapturesStdout() async throws {
        let (status, stdout, _) = try await Shell().run("/bin/echo", ["hello"])
        XCTAssertEqual(status, 0)
        let text = String(data: stdout, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("hello"), "Expected 'hello' in stdout, got: \(text)")
    }
}
