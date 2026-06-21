import XCTest
@testable import XcodeCleaner

final class SimctlParsingTests: XCTestCase {
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
}
