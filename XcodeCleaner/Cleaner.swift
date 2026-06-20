import Foundation

struct Cleaner {
    func clean(_ target: CleanupTarget) async -> Result<Void, Error> {
        do {
            switch target.kind {
            case .directory(let path):
                try removeDirectoryContents((path as NSString).expandingTildeInPath)
            case .unavailableSimulators:
                _ = try await Shell.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"])
            case .unusedRuntimes(let days):
                _ = try await Shell.run("/usr/bin/xcrun",
                    ["simctl", "runtime", "delete", "--notUsedSinceDays", String(days)])
            }
            return .success(())
        } catch { return .failure(error) }
    }

    /// Deletes everything inside `path` but keeps `path` itself.
    func removeDirectoryContents(_ path: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        for entry in try fm.contentsOfDirectory(atPath: path) {
            try fm.removeItem(atPath: (path as NSString).appendingPathComponent(entry))
        }
    }
}
