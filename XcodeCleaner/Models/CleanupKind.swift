import Foundation

enum CleanupKind: Hashable, Sendable {
    case directory(path: String)
    case unavailableSimulators
    case unusedRuntimes(days: Int)
}
