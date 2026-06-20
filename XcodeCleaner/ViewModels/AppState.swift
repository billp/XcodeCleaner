import Foundation

@MainActor
@Observable
final class AppState {
    let targets: [CleanupTarget]
    private let scanner = DiskScanner()
    private let cleaner = Cleaner()

    init() {
        targets = [
            CleanupTarget(name: "XcodeBuildMCP workspaces",
                          kind: .directory(path: "~/Library/Developer/XcodeBuildMCP/workspaces")),
            CleanupTarget(name: "Xcode DerivedData",
                          kind: .directory(path: "~/Library/Developer/Xcode/DerivedData")),
            CleanupTarget(name: "SwiftPM cache",
                          kind: .directory(path: "~/Library/Caches/org.swift.swiftpm")),
            CleanupTarget(name: "iOS DeviceSupport",
                          kind: .directory(path: "~/Library/Developer/Xcode/iOS DeviceSupport")),
            CleanupTarget(name: "Unused simulators", kind: .unavailableSimulators),
            CleanupTarget(name: "Unused simulator runtimes", kind: .unusedRuntimes(days: 30)),
        ]
    }

    func scanAll() {
        for t in targets { scan(t) }
    }

    func scan(_ target: CleanupTarget) {
        target.state = .scanning
        Task {
            let result = await scanner.size(of: target)
            switch result {
            case .success(let bytes): target.state = .scanned(bytes)
            case .failure(let err): target.state = .error(err.localizedDescription)
            }
        }
    }

    func clean(_ target: CleanupTarget) {
        target.state = .cleaning
        Task {
            let result = await cleaner.clean(target)
            switch result {
            case .success:
                let rescan = await scanner.size(of: target)
                switch rescan {
                case .success(let bytes): target.state = .cleaned(bytes)
                case .failure(let err): target.state = .error(err.localizedDescription)
                }
            case .failure(let err):
                target.state = .error(err.localizedDescription)
            }
        }
    }

    var totalText: String {
        let total = targets.compactMap(\.sizeBytes).reduce(0, +)
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
