import Foundation

protocol Cleaning: Sendable {
    func clean(_ kind: CleanupKind) async -> Result<Void, Error>
}

struct Cleaner: Cleaning {
    let runner: CommandRunning

    init(runner: CommandRunning = CommandRunner()) {
        self.runner = runner
    }

    func clean(_ kind: CleanupKind) async -> Result<Void, Error> {
        do {
            switch kind {
            case .directory(let path):
                try removeDirectoryContents((path as NSString).expandingTildeInPath)
            case .buildFolders(let root):
                try await removeBuildFolders((root as NSString).expandingTildeInPath)
            case .unavailableSimulators:
                try await runSimctl(["simctl", "delete", "unavailable"])
            case .unusedRuntimes(let days):
                try await deleteUnusedRuntimes(days: days)
            }
            return .success(())
        } catch { return .failure(error) }
    }

    /// Deletes each runtime the scan counted as unused, one identifier at a time.
    ///
    /// We deliberately don't use `simctl runtime delete --notUsedSinceDays`: it
    /// skips runtimes that have no `lastUsedAt` at all (downloaded but never
    /// booted), so a multi-GB never-used runtime would be reported as reclaimable
    /// by the scan and then silently left on disk. Resolving the identifiers here
    /// keeps the clean and the size shown in the UI in agreement.
    private func deleteUnusedRuntimes(days: Int) async throws {
        let (status, data, errData) = try await runner.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
        if status != 0 {
            let msg = String(data: errData, encoding: .utf8) ?? ""
            throw ProcessError.process(msg.isEmpty ? "exit \(status)" : msg)
        }
        guard !data.isEmpty else { return }
        for runtime in try SimctlParsing.unusedRuntimes(json: data, days: days) {
            try await runSimctl(["simctl", "runtime", "delete", runtime.identifier])
        }
    }

    /// Runs `xcrun` with the given args. A non-zero exit whose stderr says nothing
    /// matched (e.g. "No matching images found to delete" when the runtime is
    /// already gone) is treated as success — there was simply nothing to clean.
    private func runSimctl(_ args: [String]) async throws {
        let (status, _, errData) = try await runner.run("/usr/bin/xcrun", args)
        guard status != 0 else { return }
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        if stderr.localizedCaseInsensitiveContains("no matching") { return }
        throw ProcessError.process(stderr.isEmpty ? "exit \(status)" : stderr)
    }

    /// Removes every SwiftPM `.build` directory found beneath `root`, in full
    /// (unlike `removeDirectoryContents`, the `.build` folder itself goes too —
    /// SwiftPM recreates it on the next build).
    ///
    /// Tolerant of an active build churning a `.build` mid-delete: a removal is
    /// retried, and an entry that has already vanished counts as done. The
    /// authoritative check is a re-scan afterwards — an error surfaces only if a
    /// `.build` genuinely remains.
    func removeBuildFolders(_ root: String) async throws {
        let fm = FileManager.default
        var lastError: Error?
        for path in try await BuildFolders.paths(root: root, runner: runner) {
            for _ in 0..<3 {
                guard fm.fileExists(atPath: path) else { break }  // gone (lost a race) → done
                do {
                    try fm.removeItem(atPath: path)
                    break
                } catch {
                    lastError = error  // a nested file likely vanished; retry the entry
                }
            }
        }
        let remaining = try await BuildFolders.paths(root: root, runner: runner)
        if !remaining.isEmpty, let lastError {
            throw lastError
        }
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
