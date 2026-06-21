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
    ///
    /// Best-effort and tolerant of concurrent writers. Directories like
    /// `ModuleCache.noindex` are actively rewritten by an in-progress build, so
    /// an entry can vanish or change mid-delete — `FileManager.removeItem` throws
    /// in that case where `rm -rf` would not. We treat an already-gone entry as
    /// success and retry transient failures, surfacing an error only for entries
    /// that genuinely remain after the sweep.
    func removeDirectoryContents(_ path: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        var lastError: Error?
        for entry in try fm.contentsOfDirectory(atPath: path) {
            let full = (path as NSString).appendingPathComponent(entry)
            for _ in 0..<3 {
                guard fm.fileExists(atPath: full) else { break }  // gone (lost a race) → done
                do {
                    try fm.removeItem(atPath: full)
                    break
                } catch {
                    lastError = error  // a nested file likely vanished; retry the entry
                }
            }
        }
        // The directory's final state is the source of truth: if it's empty the
        // clean succeeded regardless of per-entry hiccups along the way.
        let remaining = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        if !remaining.isEmpty, let lastError {
            throw lastError
        }
    }
}
