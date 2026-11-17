import XCTest
@testable import XcodeCleaner

@MainActor
final class CleanerViewModelTests: XCTestCase {
    /// Polls until `cond` is true or the timeout elapses (ViewModel mutates state from an async Task).
    private func waitUntil(timeout: TimeInterval = 2.0, _ cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testScanSetsScannedBytes() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(123)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true),
                                  buildDetector: FakeBuildDetector.idle)
        let target = vm.targets[0]
        vm.scan(target)
        await waitUntil { if case .scanned = target.state { return true }; return false }
        XCTAssertEqual(target.sizeBytes, 123)
    }

    func testFullDiskAccessReflectsChecker() {
        let denied = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                      cleaner: FakeCleaner(result: .success(())),
                                      availability: FakeAvailability(existsResult: true),
                                      fullDiskAccess: FakeFullDiskAccess(granted: false),
                                      buildDetector: FakeBuildDetector.idle)
        XCTAssertFalse(denied.hasFullDiskAccess)

        let granted = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                       cleaner: FakeCleaner(result: .success(())),
                                       availability: FakeAvailability(existsResult: true),
                                       fullDiskAccess: FakeFullDiskAccess(granted: true),
                                       buildDetector: FakeBuildDetector.idle)
        granted.refreshFullDiskAccess()
        XCTAssertTrue(granted.hasFullDiskAccess)
    }

    func testCacheServesSizeWithinTTL() async {
        let scanner = FakeScanner(result: .success(500))
        let vm = CleanerViewModel(scanner: scanner,
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true),
                                  fullDiskAccess: FakeFullDiskAccess(granted: true),
                                  buildDetector: FakeBuildDetector.idle)
        let target = vm.targets[0]
        vm.scan(target)
        await waitUntil { if case .scanned = target.state { return true }; return false }
        XCTAssertEqual(scanner.callCount, 1)

        // Value is fresh → a second auto-scan is skipped, no new scanner call.
        vm.scan(target)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(scanner.callCount, 1)
        XCTAssertEqual(target.sizeBytes, 500)
    }

    func testForceRescanBypassesCache() async {
        let scanner = FakeScanner(results: [.success(500), .success(700)])
        let vm = CleanerViewModel(scanner: scanner,
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true),
                                  fullDiskAccess: FakeFullDiskAccess(granted: true),
                                  buildDetector: FakeBuildDetector.idle)
        let target = vm.targets[0]
        vm.scan(target)
        await waitUntil { target.sizeBytes == 500 }
        vm.scan(target, force: true)
        await waitUntil { target.sizeBytes == 700 }
        XCTAssertEqual(scanner.callCount, 2)
    }

    func testExpiredCacheTriggersRescan() async {
        let scanner = FakeScanner(results: [.success(500), .success(900)])
        let vm = CleanerViewModel(scanner: scanner,
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true),
                                  fullDiskAccess: FakeFullDiskAccess(granted: true),
                                  buildDetector: FakeBuildDetector.idle,
                                  cacheTTL: 600)
        let target = vm.targets[0]
        vm.scan(target)
        await waitUntil { target.sizeBytes == 500 }
        // Age the cached value past the TTL, then an auto-scan recomputes it.
        target.scannedAt = Date().addingTimeInterval(-601)
        vm.scan(target)
        await waitUntil { target.sizeBytes == 900 }
        XCTAssertEqual(scanner.callCount, 2)
    }

    func testScanFailureSetsError() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .failure(ProcessError.process("x"))),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true),
                                  buildDetector: FakeBuildDetector.idle)
        let target = vm.targets[0]
        vm.scan(target)
        await waitUntil { if case .error = target.state { return true }; return false }
        if case .error = target.state {} else { XCTFail("expected .error state") }
    }

    func testCleanSetsCleanedBytes() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true),
                                  buildDetector: FakeBuildDetector.idle)
        let target = vm.targets[0]
        vm.clean(target)
        await waitUntil { if case .cleaned = target.state { return true }; return false }
        XCTAssertEqual(target.sizeBytes, 0)
    }

    func testCleanFailureSetsError() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .failure(ProcessError.process("y"))),
                                  availability: FakeAvailability(existsResult: true),
                                  buildDetector: FakeBuildDetector.idle)
        let target = vm.targets[0]
        vm.clean(target)
        await waitUntil { if case .error = target.state { return true }; return false }
        if case .error = target.state {} else { XCTFail("expected .error state") }
    }

    func testXcodeBuildMCPRowPresentWhenInstalled() {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true),
                                  buildDetector: FakeBuildDetector.idle)
        XCTAssertEqual(vm.targets.first?.name, "XcodeBuildMCP workspaces")
        XCTAssertTrue(vm.targets.contains { $0.name == "XcodeBuildMCP workspaces" })
    }

    func testXcodeBuildMCPRowAbsentWhenNotInstalled() {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: false),
                                  buildDetector: FakeBuildDetector.idle)
        XCTAssertFalse(vm.targets.contains { $0.name == "XcodeBuildMCP workspaces" })
        XCTAssertEqual(vm.targets.first?.name, "Xcode DerivedData")
    }

    func testRunScheduledCleanReclaimsAndClearsFlag() async {
        let scanner = FakeScanner(results: [.success(0)]) // after
        let vm = CleanerViewModel(scanner: scanner,
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: false),
                                  buildDetector: FakeBuildDetector.idle)
        let target = vm.targets.first!
        target.state = .scanned(bytes: 1000)
        let result = await vm.runScheduledClean(named: [target.name])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.reclaimed, 1000)
        XCTAssertFalse(vm.isScheduledCleaning)
    }

    /// No `du` before deleting: the last scanned size is "before", even while a
    /// rescan is in flight.
    func testCleanDoesNotMeasureBeforeDeleting() async {
        let scanner = FakeScanner(results: [.success(200)]) // after
        let vm = CleanerViewModel(scanner: scanner,
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: false),
                                  buildDetector: FakeBuildDetector.idle)
        let target = vm.targets.first!
        target.state = .scanned(bytes: 1000)
        target.state = .scanning
        let result = await vm.runScheduledClean(named: [target.name])
        XCTAssertEqual(scanner.callCount, 1, "only the after-clean scan")
        XCTAssertEqual(result.reclaimed, 800)
    }

    /// Never scanned: the change in free space stands in for the size.
    func testNeverScannedTargetReportsFreedSpace() async {
        let disk = FakeDiskSpace(available: 100, total: 1000)
        let cleaner = CallbackCleaner { disk.space = DiskSpace(availableBytes: 400, totalBytes: 1000) }
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: false),
                                  diskSpace: disk,
                                  buildDetector: FakeBuildDetector.idle)
        let result = await vm.runScheduledClean(named: [vm.targets.first!.name])
        XCTAssertEqual(result.reclaimed, 300)
    }

    func testManualCleanShowsRowSpinnerNotBanner() async {
        let gate = CleanGate()
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: gate,
                                  availability: FakeAvailability(existsResult: false),
                                  buildDetector: FakeBuildDetector.idle)
        let target = vm.targets[0]
        XCTAssertNil(vm.statusText)

        vm.clean(target)                     // fire-and-forget Task
        await gate.waitUntilStarted()        // clean is now in-flight
        // The row shows the spinner via .cleaning; no global banner for manual cleans.
        XCTAssertEqual(target.state, .cleaning)
        XCTAssertNil(vm.statusText)

        gate.release()
        await waitUntil { if case .cleaned = target.state { return true }; return false }
        XCTAssertNil(vm.statusText)
    }

    func testCleanAllCleansEveryNonZeroTarget() async {
        let cleaner = FakeCleaner(result: .success(()))
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(1000)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: false),
                                  buildDetector: FakeBuildDetector.idle)
        vm.scanAll()                                   // every target → 1000 bytes
        await waitUntil { vm.targets.allSatisfy { $0.sizeBytes == 1000 } }
        let expected = Set(vm.targets.map(\.kind))
        vm.cleanAll()
        await waitUntil { Set(cleaner.cleanedKinds) == expected }
        XCTAssertEqual(Set(cleaner.cleanedKinds), expected)
    }

    func testCleanAllTracksBatchProgress() async {
        let gate = BatchCleanGate()
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(1000)),
                                  cleaner: gate,
                                  availability: FakeAvailability(existsResult: false),
                                  buildDetector: FakeBuildDetector.idle)
        vm.scanAll()
        await waitUntil { vm.targets.allSatisfy { $0.sizeBytes == 1000 } }
        let n = vm.targets.count

        vm.cleanAll()
        await waitUntil { gate.startedCount == n }   // all cleans now in-flight
        XCTAssertTrue(vm.isCleaningAll)
        XCTAssertEqual(vm.cleanAllTotal, n)
        XCTAssertEqual(vm.cleanAllCompleted, 0)

        gate.releaseAll()
        await waitUntil { !vm.isCleaningAll }         // batch finished → reset
        XCTAssertEqual(vm.cleanAllTotal, 0)
    }

    func testCleanAllSkipsZeroSizedTargets() async {
        let cleaner = FakeCleaner(result: .success(()))
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: false),
                                  buildDetector: FakeBuildDetector.idle)
        vm.scanAll()                                   // every target → 0 bytes
        await waitUntil { vm.targets.allSatisfy { $0.sizeBytes == 0 } }
        vm.cleanAll()
        try? await Task.sleep(nanoseconds: 100_000_000)  // let any (wrong) cleans run
        XCTAssertTrue(cleaner.cleanedKinds.isEmpty)
    }

    func testScanAllPreservesCleaningTarget() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(123)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: false),
                                  buildDetector: FakeBuildDetector.idle)
        let cleaning = vm.targets[0]
        let idle = vm.targets[1]
        cleaning.state = .cleaning           // simulate an in-flight clean

        vm.scanAll()                         // mimics the onAppear auto-rescan

        // The busy row keeps its cleaning state…
        XCTAssertEqual(cleaning.state, .cleaning)
        // …while an idle row still rescans.
        await waitUntil { idle.sizeBytes == 123 }
        XCTAssertEqual(idle.sizeBytes, 123)
        XCTAssertEqual(cleaning.state, .cleaning)
    }

    func testScanSkipsAlreadyScanningTarget() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(123)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: false),
                                  buildDetector: FakeBuildDetector.idle)
        let target = vm.targets[0]
        target.state = .scanning

        vm.scan(target)          // should be a no-op, not restart a scan

        // Give any (wrong) scan Task a chance to run, then confirm state unchanged.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(target.state, .scanning)
    }
}

/// Runs `onClean` inside every clean (e.g. to change the fake free space).
private struct CallbackCleaner: Cleaning, @unchecked Sendable {
    let onClean: () -> Void
    func clean(_ kind: CleanupKind) async -> Result<Void, Error> {
        onClean()
        return .success(())
    }
}
