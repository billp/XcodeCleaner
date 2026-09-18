import Foundation

enum SimctlParsing {
    /// A simulator runtime that qualifies for deletion.
    struct UnusedRuntime: Equatable, Sendable {
        let identifier: String
        let sizeBytes: Int64
    }

    /// Runtimes not used within the last `days` days, as reported by
    /// `simctl runtime list -j`. Runtimes with no `lastUsedAt` (downloaded but
    /// never booted) count as unused; ones marked `deletable: false` are skipped
    /// since their space can't be reclaimed.
    static func unusedRuntimes(json: Data, days: Int, now: Date = Date()) throws -> [UnusedRuntime] {
        struct Runtime: Decodable {
            let identifier: String?
            let sizeBytes: Int64?
            let lastUsedAt: String?
            let deletable: Bool?
        }
        let map = try JSONDecoder().decode([String: Runtime].self, from: json)
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var result: [UnusedRuntime] = []
        for (key, rt) in map {
            guard let size = rt.sizeBytes else { continue }
            guard rt.deletable != false else { continue }
            if let used = date(from: rt.lastUsedAt), used >= cutoff {
                continue // recently used → keep
            }
            result.append(UnusedRuntime(identifier: rt.identifier ?? key, sizeBytes: size))
        }
        return result.sorted { $0.identifier < $1.identifier }
    }

    /// Sum of `unusedRuntimes` sizes — what a clean would reclaim.
    static func unusedRuntimeBytes(json: Data, days: Int, now: Date = Date()) throws -> Int64 {
        try unusedRuntimes(json: json, days: days, now: now).reduce(0) { $0 + $1.sizeBytes }
    }

    /// A simulator clone `xcodebuild` created for a parallel test run, as
    /// reported by `simctl --set <XCTestDevices> list devices -j`.
    struct TestClone: Equatable, Sendable {
        let udid: String
        let isAvailable: Bool
        let isShutdown: Bool
        /// `nil` when simctl reports no boot date for the clone — see
        /// `staleTestClones`, which then falls back to a filesystem stamp.
        let lastBootedAt: Date?
    }

    /// Every clone in the test device set, whatever its age or state.
    static func testClones(json: Data) throws -> [TestClone] {
        struct Root: Decodable { let devices: [String: [Device]] }
        struct Device: Decodable {
            let udid: String
            let isAvailable: Bool?
            let availabilityError: String?
            let state: String?
            let lastBootedAt: String?
        }
        let root = try JSONDecoder().decode(Root.self, from: json)
        return root.devices.values.flatMap { list in
            list.map { d in
                TestClone(udid: d.udid,
                          isAvailable: d.isAvailable != false && d.availabilityError == nil,
                          isShutdown: (d.state ?? "Shutdown") == "Shutdown",
                          lastBootedAt: date(from: d.lastBootedAt))
            }
        }
        .sorted { $0.udid < $1.udid }
    }

    /// The clones a clean would delete.
    ///
    /// Two kinds qualify. An unavailable clone has lost its runtime and can
    /// never boot again, so its age is irrelevant. An available one is only
    /// taken once it has been shut down and untouched for `days` days — a
    /// booted clone, or one from a run that is still going, is left alone.
    ///
    /// simctl often reports no `lastBootedAt` for a clone, so the caller
    /// supplies `lastTouched` (the device directory's modification date) as a
    /// fallback; the newer of the two decides. A clone with neither stamp is
    /// treated as in use and kept.
    static func staleTestClones(json: Data,
                                days: Int,
                                now: Date = Date(),
                                lastTouched: (TestClone) -> Date?) throws -> [TestClone] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return try testClones(json: json).filter { clone in
            guard clone.isAvailable else { return true }
            guard clone.isShutdown else { return false }
            guard let used = [clone.lastBootedAt, lastTouched(clone)].compactMap({ $0 }).max() else {
                return false
            }
            return used < cutoff
        }
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

    /// simctl writes ISO8601 dates with or without fractional seconds
    /// depending on the field, so try both.
    private static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return basic.date(from: string) ?? fractional.date(from: string)
    }
}
