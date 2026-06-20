import Foundation

enum SimctlParsing {
    /// Sum sizeBytes of runtimes not used within the last `days` days.
    /// Runtimes with no lastUsedAt are treated as unused.
    static func unusedRuntimeBytes(json: Data, days: Int, now: Date = Date()) throws -> Int64 {
        struct Runtime: Decodable { let sizeBytes: Int64?; let lastUsedAt: String? }
        let map = try JSONDecoder().decode([String: Runtime].self, from: json)
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let fmt = ISO8601DateFormatter()
        var total: Int64 = 0
        for rt in map.values {
            guard let size = rt.sizeBytes else { continue }
            if let s = rt.lastUsedAt, let used = fmt.date(from: s), used >= cutoff {
                continue // recently used → keep
            }
            total += size
        }
        return total
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
