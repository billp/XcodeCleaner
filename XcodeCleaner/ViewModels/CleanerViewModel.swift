import Foundation

@MainActor
@Observable
final class CleanerViewModel {
    let targets: [CleanupTarget]
    private let scanner: DiskScanning
    private let cleaner: Cleaning
    private let availability: AvailabilityChecking
    private let fullDiskAccess: FullDiskAccessChecking
    private let diskSpaceProvider: DiskSpaceProviding
    private let buildDetector: BuildDetecting
    /// How long a computed size stays fresh before an auto-scan recomputes it.
    /// The top ↻ button bypasses this to force a full rescan.
    private let cacheTTL: TimeInterval

    /// Set while an unattended (scheduled or low-disk) clean is running.
    private(set) var autoCleanTrigger: AutoCleanTrigger?
    var isScheduledCleaning: Bool { autoCleanTrigger != nil }
    private(set) var cleanAllTotal = 0
    private(set) var cleanAllCompleted = 0
    var isCleaningAll: Bool { cleanAllTotal > 0 }

    /// Whether the app can scan `~` without tripping macOS privacy prompts.
    /// Re-checked whenever the menu opens so it clears once the user grants access.
    private(set) var hasFullDiskAccess = true

    /// Capacity of the startup volume; refreshed when the menu opens and after cleans.
    private(set) var diskSpace: DiskSpace?

    /// Builds running right now (Xcode, xcodebuild from MCP servers/scripts, SwiftPM…).
    /// Polled while the menu is open.
    private(set) var activeBuilds: [ActiveBuild] = []

    /// A manual clean the user asked for while builds were running; awaiting
    /// confirmation from the warning banner.
    enum PendingClean {
        case target(CleanupTarget)
        case all
    }
    private(set) var pendingClean: PendingClean?

    init(scanner: DiskScanning = DiskScanner(),
         cleaner: Cleaning = Cleaner(),
         availability: AvailabilityChecking = AvailabilityChecker(),
         fullDiskAccess: FullDiskAccessChecking = FullDiskAccessChecker(),
         diskSpace: DiskSpaceProviding = DiskSpaceReader(),
         buildDetector: BuildDetecting = BuildDetector(),
         cacheTTL: TimeInterval = 600) {
        self.scanner = scanner
        self.cleaner = cleaner
        self.availability = availability
        self.fullDiskAccess = fullDiskAccess
        self.diskSpaceProvider = diskSpace
        self.buildDetector = buildDetector
        self.cacheTTL = cacheTTL
        hasFullDiskAccess = fullDiskAccess.isGranted()
        self.diskSpace = diskSpace.current()
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

    /// Re-reads the volume's capacity and returns the fresh value.
    @discardableResult
    func refreshDiskSpace() -> DiskSpace? {
        diskSpace = diskSpaceProvider.current()
        return diskSpace
    }

    var isDiskSpaceLow: Bool {
        diskSpace.map(LowDiskMath.isLow) ?? false
    }

    /// Re-detects running builds; returns them, or `nil` if the process list
    /// couldn't be read (the last known value is kept in that case).
    @discardableResult
    func refreshActiveBuilds() async -> [ActiveBuild]? {
        guard let builds = try? await buildDetector.activeBuilds() else { return nil }
        activeBuilds = builds
        return builds
    }

    /// Manual per-row clean: runs immediately unless builds are active, in which
    /// case it waits for the user to confirm via `confirmPendingClean()`.
    func requestClean(_ target: CleanupTarget) async {
        if await (refreshActiveBuilds() ?? []).isEmpty {
            clean(target)
        } else {
            pendingClean = .target(target)
        }
    }

    /// Manual "Clean All": same build check as `requestClean`.
    func requestCleanAll() async {
        if await (refreshActiveBuilds() ?? []).isEmpty {
            cleanAll()
        } else {
            pendingClean = .all
        }
    }

    func confirmPendingClean() {
        guard let pending = pendingClean else { return }
        pendingClean = nil
        switch pending {
        case .target(let target): clean(target)
        case .all: cleanAll()
        }
    }

    func cancelPendingClean() {
        pendingClean = nil
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

    /// Paths running builds are using, which every clean leaves alone; empty
    /// when the process list can't be read (a manual clean still goes ahead —
    /// the user already confirmed it if builds were showing).
    func pathsInUse() async -> Set<String> {
        (try? await buildDetector.pathsInUse()) ?? []
    }

    func clean(_ target: CleanupTarget) {
        Task { _ = await performClean(target, sparing: await pathsInUse()) }
    }

    /// Cleans every target that has something to clean (manual "Clean All");
    /// skips rows whose size is zero. Each runs concurrently while the batch's
    /// total progress (completed / total) is tracked for the UI.
    func cleanAll() {
        let toClean = targets.filter { $0.sizeBytes != 0 }
        guard !toClean.isEmpty else { return }
        cleanAllCompleted = 0
        cleanAllTotal = toClean.count
        let inUse = Task { await pathsInUse() }
        for target in toClean {
            Task {
                _ = await performClean(target, sparing: await inUse.value)
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
    /// Cleans one target, returning bytes reclaimed (before − after). Entries
    /// holding any of `inUse` are left alone.
    private func performClean(_ target: CleanupTarget, sparing inUse: Set<String>) async -> Int64 {
        var before = target.sizeBytes
        if before == nil, case .success(let b) = await scanner.size(of: target.kind) {
            before = b
        }
        target.state = .cleaning
        let result = await cleaner.clean(target.kind, sparing: inUse)
        switch result {
        case .success:
            switch await scanner.size(of: target.kind) {
            case .success(let after):
                target.state = .cleaned(bytes: after)
                target.scannedAt = Date()
                refreshDiskSpace()
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

    /// Cleans all named targets in sequence, leaving alone entries holding any of
    /// `inUse`; returns count cleaned + total reclaimed.
    func runScheduledClean(named names: Set<String>,
                           trigger: AutoCleanTrigger = .scheduled,
                           sparing inUse: Set<String> = []) async -> (count: Int, reclaimed: Int64) {
        autoCleanTrigger = trigger
        defer { autoCleanTrigger = nil }
        var reclaimed: Int64 = 0
        var count = 0
        for target in targets where names.contains(target.name) {
            reclaimed += await performClean(target, sparing: inUse)
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
        switch autoCleanTrigger {
        case .scheduled: "Scheduled clean in progress…"
        case .lowDisk: "Low disk space — cleaning…"
        case nil: nil
        }
    }
}
