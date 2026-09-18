import Foundation

@MainActor
@Observable
final class CleanerViewModel {
    let targets: [CleanupTarget]
    private let scanner: DiskScanning
    private let cleaner: Cleaning
    private let availability: AvailabilityChecking
    private let fullDiskAccess: FullDiskAccessChecking
    /// How long a computed size stays fresh before an auto-scan recomputes it.
    /// The top ↻ button bypasses this to force a full rescan.
    private let cacheTTL: TimeInterval

    private(set) var isScheduledCleaning = false
    private(set) var cleanAllTotal = 0
    private(set) var cleanAllCompleted = 0
    var isCleaningAll: Bool { cleanAllTotal > 0 }

    /// Whether the app can scan `~` without tripping macOS privacy prompts.
    /// Re-checked whenever the menu opens so it clears once the user grants access.
    private(set) var hasFullDiskAccess = true

    init(scanner: DiskScanning = DiskScanner(),
         cleaner: Cleaning = Cleaner(),
         availability: AvailabilityChecking = AvailabilityChecker(),
         fullDiskAccess: FullDiskAccessChecking = FullDiskAccessChecker(),
         cacheTTL: TimeInterval = 600) {
        self.scanner = scanner
        self.cleaner = cleaner
        self.availability = availability
        self.fullDiskAccess = fullDiskAccess
        self.cacheTTL = cacheTTL
        hasFullDiskAccess = fullDiskAccess.isGranted()
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
        built.append(CleanupTarget(name: "SwiftPM .build folders",
                                   kind: .buildFolders(root: "~")))
        built.append(CleanupTarget(name: "iOS DeviceSupport",
                                   kind: .directory(path: "~/Library/Developer/Xcode/iOS DeviceSupport")))
        built.append(CleanupTarget(name: "Unused simulators", kind: .unavailableSimulators))
        built.append(CleanupTarget(name: "Unused simulator runtimes", kind: .unusedRuntimes(days: 30)))
        if availability.exists(TestClones.defaultSetPath) {
            built.append(CleanupTarget(name: "Leftover test simulators",
                                       kind: .staleTestClones(days: 1)))
        }
        targets = built
    }

    /// Scans every target. `force: true` (the top ↻ button) recomputes all of
    /// them; otherwise targets with a size younger than `cacheTTL` are skipped.
    func scanAll(force: Bool = false) {
        for t in targets { scan(t, force: force) }
    }

    func refreshFullDiskAccess() {
        hasFullDiskAccess = fullDiskAccess.isGranted()
    }

    /// A target's cached size is still fresh if it has a value stamped within `cacheTTL`.
    private func isFresh(_ target: CleanupTarget) -> Bool {
        guard target.sizeBytes != nil, let at = target.scannedAt else { return false }
        return Date().timeIntervalSince(at) < cacheTTL
    }

    func scan(_ target: CleanupTarget, force: Bool = false) {
        switch target.state {
        case .scanning, .cleaning: return   // don't disturb in-flight work
        default: break
        }
        if !force && isFresh(target) { return }   // serve the cached size
        target.state = .scanning
        Task {
            let result = await scanner.size(of: target.kind)
            switch result {
            case .success(let bytes):
                target.state = .scanned(bytes: bytes)
                target.scannedAt = Date()
            case .failure(let err):
                target.state = .error(message: err.localizedDescription)
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
    private func performClean(_ target: CleanupTarget) async -> Int64 {
        var before = target.sizeBytes
        if before == nil, case .success(let b) = await scanner.size(of: target.kind) {
            before = b
        }
        target.state = .cleaning
        let result = await cleaner.clean(target.kind)
        switch result {
        case .success:
            switch await scanner.size(of: target.kind) {
            case .success(let after):
                target.state = .cleaned(bytes: after)
                target.scannedAt = Date()
                return max(0, (before ?? after) - after)
            case .failure(let err):
                target.state = .error(message: err.localizedDescription)
                return 0
            }
        case .failure(let err):
            target.state = .error(message: err.localizedDescription)
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
