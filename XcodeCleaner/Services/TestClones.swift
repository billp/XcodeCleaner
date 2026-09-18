import Foundation

/// Locates the simulator clones `xcodebuild` creates for parallel testing.
///
/// Those clones live in their own simctl device set under
/// `~/Library/Developer/XCTestDevices`, not the default one, so
/// `simctl list devices` never mentions them and the "Unused simulators"
/// target can't see them. A test run that finishes normally deletes its own
/// clones; a run that crashes or is cancelled leaves them behind, and each is
/// a multi-GB copy of a full simulator — they pile up unnoticed.
enum TestClones {
    static let setPath = "~/Library/Developer/XCTestDevices"

    static var defaultSetPath: String { (setPath as NSString).expandingTildeInPath }

    /// The clones a clean would delete, per `SimctlParsing.staleTestClones`.
    /// An absent set directory means no clones were ever made.
    static func stale(days: Int,
                      runner: CommandRunning,
                      setPath: String = defaultSetPath,
                      now: Date = Date()) async throws -> [SimctlParsing.TestClone] {
        guard FileManager.default.fileExists(atPath: setPath) else { return [] }
        let (status, data, errData) = try await runner.run(
            "/usr/bin/xcrun", ["simctl", "--set", setPath, "list", "devices", "-j"]
        )
        if status != 0 {
            let msg = String(data: errData, encoding: .utf8) ?? ""
            throw ProcessError.process(msg.isEmpty ? "exit \(status)" : msg)
        }
        guard !data.isEmpty else { return [] }
        return try SimctlParsing.staleTestClones(json: data, days: days, now: now) { clone in
            modificationDate(of: directoryPath(of: clone, setPath: setPath))
        }
    }

    /// Where a clone's data lives — the directory a delete reclaims.
    static func directoryPath(of clone: SimctlParsing.TestClone, setPath: String = defaultSetPath) -> String {
        (setPath as NSString).appendingPathComponent(clone.udid)
    }

    private static func modificationDate(of path: String) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }
}
