import Foundation

@MainActor
@Observable
final class CleanerViewModel {
    let targets: [CleanupTarget]
    private let scanner: DiskScanning
    private let cleaner: Cleaning
    private let availability: AvailabilityChecking

    init(scanner: DiskScanning = DiskScanner(),
         cleaner: Cleaning = Cleaner(),
         availability: AvailabilityChecking = FileManagerAvailability()) {
        self.scanner = scanner
        self.cleaner = cleaner
        self.availability = availability
        var built: [CleanupTarget] = []
        let xbmcpPath = "~/Library/Developer/XcodeBuildMCP/workspaces"
        if availability.exists((xbmcpPath as NSString).expandingTildeInPath) {
            built.append(CleanupTarget(name: "XcodeBuildMCP workspaces",
                                       kind: .directory(path: xbmcpPath)))
        }
        built.append(CleanupTarget(name: "Xcode DerivedData",
                                   kind: .directory(path: "~/Library/Developer/Xcode/DerivedData")))
        built.append(CleanupTarget(name: "SwiftPM cache",
                                   kind: .directory(path: "~/Library/Caches/org.swift.swiftpm")))
        built.append(CleanupTarget(name: "iOS DeviceSupport",
                                   kind: .directory(path: "~/Library/Developer/Xcode/iOS DeviceSupport")))
        built.append(CleanupTarget(name: "Unused simulators", kind: .unavailableSimulators))
        built.append(CleanupTarget(name: "Unused simulator runtimes", kind: .unusedRuntimes(days: 30)))
        targets = built
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
