import Foundation

/// A snapshot of the startup volume's capacity.
struct DiskSpace: Equatable, Sendable {
    let availableBytes: Int64
    let totalBytes: Int64

    /// Free space as a fraction of the volume (0…1).
    var freeFraction: Double {
        totalBytes > 0 ? Double(availableBytes) / Double(totalBytes) : 1
    }

    var availableText: String {
        ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
    }

    var totalText: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var percentFreeText: String {
        freeFraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

protocol DiskSpaceProviding: Sendable {
    func current() -> DiskSpace?
}

/// Reads the home volume's capacity. "Available" uses the same figure Finder
/// shows (free space plus purgeable space macOS can reclaim on demand).
struct DiskSpaceReader: DiskSpaceProviding {
    func current() -> DiskSpace? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
        ]), let total = values.volumeTotalCapacity
        else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init)
        guard let available else { return nil }
        return DiskSpace(availableBytes: available, totalBytes: Int64(total))
    }
}

enum LowDiskMath {
    /// Auto-clean kicks in when free space drops below this fraction of the disk.
    static let threshold = 0.10
    /// Minimum gap between low-disk cleans, so a clean that can't lift free space
    /// back above the threshold doesn't re-run on every tick.
    static let cooldown: TimeInterval = 6 * 60 * 60

    static func isLow(_ space: DiskSpace) -> Bool {
        space.freeFraction < threshold
    }

    static func shouldClean(space: DiskSpace, lastRun: Date?, now: Date) -> Bool {
        guard isLow(space) else { return false }
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= cooldown
    }
}
