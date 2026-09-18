import Foundation

private func decode(_ data: Data) -> String { String(data: data, encoding: .utf8) ?? "" }

protocol DiskScanning: Sendable {
    func size(of kind: CleanupKind) async -> Result<Int64, Error>
}

struct DiskScanner: DiskScanning {
    let runner: CommandRunning

    init(runner: CommandRunning = CommandRunner()) {
        self.runner = runner
    }

    func size(of kind: CleanupKind) async -> Result<Int64, Error> {
        do {
            switch kind {
            case .directory(let path):
                return .success(try await directoryBytes(expand(path)))
            case .buildFolders(let root):
                return .success(try await buildFoldersBytes(expand(root)))
            case .unavailableSimulators:
                return .success(try await unavailableSimulatorBytes())
            case .unusedRuntimes(let days):
                return .success(try await unusedRuntimeBytes(days: days))
            case .staleTestClones(let days):
                return .success(try await staleTestCloneBytes(days: days))
            }
        } catch { return .failure(error) }
    }

    private func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// `du -sk` → kilobytes; 0 if the path doesn't exist.
    private func directoryBytes(_ path: String) async throws -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let (status, data, errData) = try await runner.run("/usr/bin/du", ["-sk", path])
        if let text = String(data: data, encoding: .utf8),
           let kbStr = text.split(separator: "\t").first,
           let kb = Int64(kbStr.trimmingCharacters(in: .whitespaces)) {
            return kb * 1024
        }
        // Parsing failed — surface the error only if du also reported failure
        if status != 0 {
            let msg = decode(errData)
            throw ProcessError.process(msg.isEmpty ? "exit \(status)" : msg)
        }
        return 0
    }

    /// Sum of every `.build` directory beneath `root`. Each is measured with the
    /// same `du -sk` path as a plain directory target; a `.build` that vanishes
    /// mid-scan (an active build) simply contributes 0.
    private func buildFoldersBytes(_ root: String) async throws -> Int64 {
        let paths = try await BuildFolders.paths(root: root, runner: runner)
        var total: Int64 = 0
        for path in paths {
            total += try await directoryBytes(path)
        }
        return total
    }

    private func unusedRuntimeBytes(days: Int) async throws -> Int64 {
        let (status, data, errData) = try await runner.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
        if status != 0 {
            let msg = decode(errData)
            throw ProcessError.process(msg.isEmpty ? "exit \(status)" : msg)
        }
        guard !data.isEmpty else { return 0 }
        return try SimctlParsing.unusedRuntimeBytes(json: data, days: days)
    }

    /// Measured with `du -sk` per clone directory rather than simctl's
    /// `dataPathSize`, which counts only the clone's `data` subdirectory —
    /// the delete reclaims the whole directory, so that's what we report.
    private func staleTestCloneBytes(days: Int) async throws -> Int64 {
        var total: Int64 = 0
        for clone in try await TestClones.stale(days: days, runner: runner) {
            total += try await directoryBytes(TestClones.directoryPath(of: clone))
        }
        return total
    }

    private func unavailableSimulatorBytes() async throws -> Int64 {
        let (status, data, errData) = try await runner.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"])
        if status != 0 {
            let msg = decode(errData)
            throw ProcessError.process(msg.isEmpty ? "exit \(status)" : msg)
        }
        guard !data.isEmpty else { return 0 }
        let udids = try SimctlParsing.unavailableDeviceUDIDs(json: data)
        let base = (("~/Library/Developer/CoreSimulator/Devices") as NSString).expandingTildeInPath
        var total: Int64 = 0
        for udid in udids {
            total += try await directoryBytes("\(base)/\(udid)")
        }
        return total
    }
}
