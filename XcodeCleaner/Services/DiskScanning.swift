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
            case .unavailableSimulators:
                return .success(try await unavailableSimulatorBytes())
            case .unusedRuntimes(let days):
                return .success(try await unusedRuntimeBytes(days: days))
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

    private func unusedRuntimeBytes(days: Int) async throws -> Int64 {
        let (status, data, errData) = try await runner.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
        if status != 0 {
            let msg = decode(errData)
            throw ProcessError.process(msg.isEmpty ? "exit \(status)" : msg)
        }
        guard !data.isEmpty else { return 0 }
        return try SimctlParsing.unusedRuntimeBytes(json: data, days: days)
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
