import Foundation

protocol FullDiskAccessChecking: Sendable {
    func isGranted() -> Bool
}

/// Detects whether the app has been granted Full Disk Access.
///
/// Scanning all of `~` for `.build` folders inevitably steps into TCC-protected
/// locations (other apps' `~/Library/Containers`, `~/.Trash`, and — if projects
/// live there — `~/Desktop`, `~/Documents`, `~/Downloads`). Without Full Disk
/// Access each raises a privacy prompt; with it, the scan runs silently.
///
/// The probe reads the user's TCC database, which is readable *only* with Full
/// Disk Access and is denied silently (never prompts) otherwise — so a
/// successful read is a reliable, side-effect-free signal that FDA is granted.
struct FullDiskAccessChecker: FullDiskAccessChecking {
    func isGranted() -> Bool {
        let path = ("~/Library/Application Support/com.apple.TCC/TCC.db" as NSString)
            .expandingTildeInPath
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return false
        }
        defer { try? handle.close() }
        // A protected file can open but still fail at read time when access is
        // denied, so require an actual byte to come back.
        return (try? handle.read(upToCount: 1)) != nil
    }
}
