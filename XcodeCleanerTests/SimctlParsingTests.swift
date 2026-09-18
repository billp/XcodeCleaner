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

    func testUnusedRuntimesIncludesNeverUsedAndSkipsUndeletable() throws {
        // A never-used runtime has no `lastUsedAt` at all — it must still be
        // listed, since that is precisely what `simctl --notUsedSinceDays` misses.
        let json = """
        {
          "A": { "identifier": "A", "sizeBytes": 8000000000 },
          "B": { "identifier": "B", "sizeBytes": 7000000000, "deletable": false },
          "C": { "identifier": "C", "sizeBytes": 300, "lastUsedAt": "2026-06-20T12:00:00Z" }
        }
        """.data(using: .utf8)!
        let now = ISO8601DateFormatter().date(from: "2026-06-20T13:00:00Z")!
        let unused = try SimctlParsing.unusedRuntimes(json: json, days: 30, now: now)
        XCTAssertEqual(unused, [.init(identifier: "A", sizeBytes: 8_000_000_000)])
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

    /// simctl sometimes does report `lastBootedAt`; when it and the filesystem
    /// stamp disagree, the newer one decides so a clone in use is never taken.
    func testStaleTestClonesUsesNewestOfBootDateAndFileStamp() throws {
        let json = """
        { "devices": { "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
          { "udid": "BOOTED_RECENTLY", "isAvailable": true, "state": "Shutdown",
            "lastBootedAt": "2026-06-20T12:00:00Z" },
          { "udid": "TOUCHED_RECENTLY", "isAvailable": true, "state": "Shutdown",
            "lastBootedAt": "2026-01-01T12:00:00Z" },
          { "udid": "COLD", "isAvailable": true, "state": "Shutdown",
            "lastBootedAt": "2026-01-01T12:00:00Z" }
        ] } }
        """.data(using: .utf8)!
        let now = ISO8601DateFormatter().date(from: "2026-06-20T13:00:00Z")!
        let fresh = ISO8601DateFormatter().date(from: "2026-06-20T11:00:00Z")!
        let old = ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z")!

        let stale = try SimctlParsing.staleTestClones(json: json, days: 1, now: now) { clone in
            clone.udid == "TOUCHED_RECENTLY" ? fresh : old
        }

        XCTAssertEqual(stale.map(\.udid), ["COLD"])
    }

    /// No boot date and no filesystem stamp means we can't tell a leftover from
    /// a clone a running test just created — keep it.
    func testStaleTestClonesKeepsCloneWithNoAgeSignal() throws {
        let json = """
        { "devices": { "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
          { "udid": "UNKNOWN", "isAvailable": true, "state": "Shutdown" }
        ] } }
        """.data(using: .utf8)!

        let stale = try SimctlParsing.staleTestClones(json: json, days: 1) { _ in nil }

        XCTAssertTrue(stale.isEmpty)
    }
}
