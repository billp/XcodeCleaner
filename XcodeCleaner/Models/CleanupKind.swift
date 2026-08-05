import Foundation

enum CleanupKind: Hashable, Sendable {
    case directory(path: String)
    /// All SwiftPM `.build` directories found beneath `root` (e.g. `~`).
    case buildFolders(root: String)
    case unavailableSimulators
    case unusedRuntimes(days: Int)

    var systemImage: String {
        switch self {
        case .directory(let path):
            if path.contains("DerivedData") { return "hammer" }
            if path.contains("swiftpm") { return "shippingbox" }
            if path.contains("DeviceSupport") { return "iphone" }
            if path.contains("XcodeBuildMCP") { return "wrench.and.screwdriver" }
            return "folder"
        case .buildFolders:
            return "hammer.circle"
        case .unavailableSimulators:
            return "iphone.slash"
        case .unusedRuntimes:
            return "memorychip"
        }
    }
}
