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
        let fmtBasic = ISO8601DateFormatter()
        fmtBasic.formatOptions = [.withInternetDateTime]
        let fmtFractional = ISO8601DateFormatter()
        fmtFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var result: [UnusedRuntime] = []
        for (key, rt) in map {
            guard let size = rt.sizeBytes else { continue }
            guard rt.deletable != false else { continue }
            if let s = rt.lastUsedAt {
                let used = fmtBasic.date(from: s) ?? fmtFractional.date(from: s)
                if let used, used >= cutoff {
                    continue // recently used → keep
                }
            }
            result.append(UnusedRuntime(identifier: rt.identifier ?? key, sizeBytes: size))
        }
        return result.sorted { $0.identifier < $1.identifier }
    }

    /// Sum of `unusedRuntimes` sizes — what a clean would reclaim.
    static func unusedRuntimeBytes(json: Data, days: Int, now: Date = Date()) throws -> Int64 {
        try unusedRuntimes(json: json, days: days, now: now).reduce(0) { $0 + $1.sizeBytes }
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
}
