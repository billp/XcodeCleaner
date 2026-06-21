import Foundation

@MainActor
@Observable
final class CleanerViewModel {
    let targets: [CleanupTarget]
    private let scanner: DiskScanning
    private let cleaner: Cleaning
    private let availability: AvailabilityChecking

    private(set) var isScheduledCleaning = false
    private(set) var cleanAllTotal = 0
    private(set) var cleanAllCompleted = 0
    var isCleaningAll: Bool { cleanAllTotal > 0 }

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
        Task { _ = await performClean(target) }
    }

    /// Cleans every target that has something to clean (manual "Clean All");
    /// skips rows whose size is zero. Each runs concurrently while the batch's
    /// total progress (completed / total) is tracked for the UI.
    func cleanAll() {
        let toClean = targets.filter { $0.sizeBytes != 0 }
        guard !toClean.isEmpty else { return }
        cleanAllCompleted = 0
        cleanAllTotal = toClean.count
        for target in toClean {
            Task {
                _ = await performClean(target)
                cleanAllCompleted += 1
                if cleanAllCompleted >= cleanAllTotal {
                    cleanAllTotal = 0
                    cleanAllCompleted = 0
                }
            }
        }
    }

    // A scheduled run and an already-in-flight manual clean can overlap; all
    // target.state writes happen on the MainActor so this is serialized and benign.
    /// Cleans one target, returning bytes reclaimed (before − after).
    private func performClean(_ target: sending CleanupTarget) async -> Int64 {
        var before = target.sizeBytes
        if before == nil, case .success(let b) = await scanner.size(of: target) {
            before = b
        }
        target.state = .cleaning
        let result = await cleaner.clean(target)
        switch result {
        case .success:
            switch await scanner.size(of: target) {
            case .success(let after):
                target.state = .cleaned(after)
                return max(0, (before ?? after) - after)
            case .failure(let err):
                target.state = .error(err.localizedDescription)
                return 0
            }
        case .failure(let err):
            target.state = .error(err.localizedDescription)
            return 0
        }
    }

    /// Cleans all named targets in sequence; returns count cleaned + total reclaimed.
    func runScheduledClean(named names: Set<String>) async -> (count: Int, reclaimed: Int64) {
        isScheduledCleaning = true
        defer { isScheduledCleaning = false }
        var reclaimed: Int64 = 0
        var count = 0
        for target in targets where names.contains(target.name) {
            reclaimed += await performClean(target)
            count += 1
        }
        return (count, reclaimed)
    }

    var totalText: String {
        let total = targets.compactMap(\.sizeBytes).reduce(0, +)
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    /// Status banner / menu bar pulse is shown only for a scheduled run. A manual
    /// per-row clean shows just the spinner in that row (via TargetState.cleaning),
    /// exactly like scanning — no global banner.
    var statusText: String? {
        isScheduledCleaning ? "Scheduled clean in progress…" : nil
    }
}
