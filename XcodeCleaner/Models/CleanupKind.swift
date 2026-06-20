import Foundation

enum CleanupKind: Equatable {
    case directory(path: String)
    case unavailableSimulators
    case unusedRuntimes(days: Int)
}
