import Foundation

protocol Cleaning: Sendable {
    func clean(_ kind: CleanupKind) async -> Result<Void, Error>
}

struct Cleaner: Cleaning {
    let runner: CommandRunning

    init(runner: CommandRunning = Shell()) {
        self.runner = runner
    }

    func clean(_ kind: CleanupKind) async -> Result<Void, Error> {
        do {
            switch kind {
            case .directory(let path):
                try removeDirectoryContents((path as NSString).expandingTildeInPath)
            case .unavailableSimulators:
                try await runSimctl(["simctl", "delete", "unavailable"])
            case .unusedRuntimes(let days):
                try await runSimctl(["simctl", "runtime", "delete", "--notUsedSinceDays", String(days)])
            }
            return .success(())
        } catch { return .failure(error) }
    }

    /// Runs `xcrun` with the given args. A non-zero exit whose stderr says nothing
    /// matched (e.g. "No matching images found to delete" when no runtimes are old
    /// enough) is treated as success — there was simply nothing to clean.
    private func runSimctl(_ args: [String]) async throws {
        let (status, _, errData) = try await runner.run("/usr/bin/xcrun", args)
        guard status != 0 else { return }
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        if stderr.localizedCaseInsensitiveContains("no matching") { return }
        throw ScanError.process(stderr.isEmpty ? "exit \(status)" : stderr)
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
