import Foundation

enum CleanupKind: Equatable {
    case directory(path: String)
    case unavailableSimulators
    case unusedRuntimes(days: Int)
}

enum TargetState: Equatable {
    case idle
    case scanning
    case scanned(Int64)
    case cleaning
    case cleaned(Int64)
    case error(String)
}

@Observable
final class CleanupTarget: Identifiable {
    let id = UUID()
    let name: String
    let kind: CleanupKind
    var state: TargetState = .idle

    init(name: String, kind: CleanupKind) {
        self.name = name
        self.kind = kind
    }

    var sizeBytes: Int64? {
        switch state {
        case .scanned(let b), .cleaned(let b): return b
        default: return nil
        }
    }

    var sizeText: String {
        switch state {
        case .idle: return "—"
        case .scanning: return "scanning…"
        case .cleaning: return "cleaning…"
        case .scanned(let b), .cleaned(let b):
            return ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
        case .error: return "error"
        }
    }
}
