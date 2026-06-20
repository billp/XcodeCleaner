import Foundation

struct Cleaner {
    func clean(_ target: CleanupTarget) async -> Result<Void, Error> {
        do {
            switch target.kind {
            case .directory(let path):
                try removeDirectoryContents((path as NSString).expandingTildeInPath)
            case .unavailableSimulators:
                let (status, _, errData) = try await Shell.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"])
                if status != 0 {
                    let msg = String(data: errData, encoding: .utf8) ?? ""
                    throw ScanError.process(msg.isEmpty ? "exit \(status)" : msg)
                }
            case .unusedRuntimes(let days):
                let (status, _, errData) = try await Shell.run("/usr/bin/xcrun",
                    ["simctl", "runtime", "delete", "--notUsedSinceDays", String(days)])
                if status != 0 {
                    let msg = String(data: errData, encoding: .utf8) ?? ""
                    throw ScanError.process(msg.isEmpty ? "exit \(status)" : msg)
                }
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
