import Foundation

enum ScanError: Error, Equatable { case process(String) }

enum Shell {
    /// Runs a process off the caller's actor, returns exit status + stdout bytes.
    static func run(_ launchPath: String, _ args: [String]) async throws -> (status: Int32, stdout: Data) {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: launchPath)
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            p.terminationHandler = { proc in
                let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
                cont.resume(returning: (proc.terminationStatus, data))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}

struct DiskScanner {
    func size(of target: CleanupTarget) async -> Result<Int64, Error> {
        do {
            switch target.kind {
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
        let (_, data) = try await Shell.run("/usr/bin/du", ["-sk", path])
        guard let text = String(data: data, encoding: .utf8),
              let kbStr = text.split(separator: "\t").first,
              let kb = Int64(kbStr.trimmingCharacters(in: .whitespaces)) else {
            return 0
        }
        return kb * 1024
    }

    private func unusedRuntimeBytes(days: Int) async throws -> Int64 {
        let (_, data) = try await Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
        guard !data.isEmpty else { return 0 }
        return try SimctlParsing.unusedRuntimeBytes(json: data, days: days)
    }

    private func unavailableSimulatorBytes() async throws -> Int64 {
        let (_, data) = try await Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"])
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
