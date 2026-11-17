import XCTest
@testable import XcodeCleaner

final class LowDiskMathTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreeFractionAndText() {
        let space = DiskSpace(availableBytes: 250, totalBytes: 1000)
        XCTAssertEqual(space.freeFraction, 0.25, accuracy: 0.0001)
        XCTAssertFalse(LowDiskMath.isLow(space))
    }

    func testZeroTotalIsNotLow() {
        XCTAssertFalse(LowDiskMath.isLow(DiskSpace(availableBytes: 0, totalBytes: 0)))
    }

    func testBelowThresholdIsLow() {
        XCTAssertTrue(LowDiskMath.isLow(DiskSpace(availableBytes: 99, totalBytes: 1000)))
        XCTAssertFalse(LowDiskMath.isLow(DiskSpace(availableBytes: 100, totalBytes: 1000)))
    }

    func testShouldCleanRespectsCooldown() {
        let low = DiskSpace(availableBytes: 50, totalBytes: 1000)
        XCTAssertTrue(LowDiskMath.shouldClean(space: low, lastRun: nil, now: now))
        XCTAssertFalse(LowDiskMath.shouldClean(space: low, lastRun: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(LowDiskMath.shouldClean(space: low, lastRun: now.addingTimeInterval(-LowDiskMath.cooldown),
                                              now: now))
    }

    func testShouldNotCleanWhenSpaceIsFine() {
        let fine = DiskSpace(availableBytes: 500, totalBytes: 1000)
        XCTAssertFalse(LowDiskMath.shouldClean(space: fine, lastRun: nil, now: now))
    }
}

@MainActor
final class LowDiskSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeSuite() -> UserDefaults {
        let name = "xclean.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    private struct Harness {
        let settings: SettingsViewModel
        let cleaner: FakeCleaner
        let vm: CleanerViewModel
        let notifier: FakeNotifier
        let scheduler: SchedulerViewModel
    }

    private func makeHarness(available: Int64, enabled: Bool = true,
                             builds: FakeBuildDetector = .idle) -> Harness {
        let settings = SettingsViewModel(userDefaults: makeSuite())
        settings.lowDiskCleanEnabled = enabled
        settings.enabledTargetNames = ["Xcode DerivedData"]
        let cleaner = FakeCleaner(result: .success(()))
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: false),
                                  fullDiskAccess: FakeFullDiskAccess(granted: true),
                                  diskSpace: FakeDiskSpace(available: available, total: 1000),
                                  buildDetector: FakeBuildDetector.idle)
        let notifier = FakeNotifier()
        let scheduler = SchedulerViewModel(vm: vm, settings: settings,
                                           buildDetector: builds,
                                           notifier: notifier)
        return Harness(settings: settings, cleaner: cleaner, vm: vm, notifier: notifier, scheduler: scheduler)
    }

    func testCleansWhenDiskIsLow() async {
        let h = makeHarness(available: 50)
        await h.scheduler.tick(now: now)
        XCTAssertEqual(h.cleaner.cleanedKinds, [.directory(path: "~/Library/Developer/Xcode/DerivedData")])
        XCTAssertEqual(h.settings.lastLowDiskClean, now)
        XCTAssertEqual(h.notifier.finishedCalls.count, 1)
        XCTAssertEqual(h.notifier.finishedCalls.first?.trigger, .lowDisk)
        XCTAssertFalse(h.vm.isScheduledCleaning)
    }

    func testDoesNothingWhenDisabled() async {
        let h = makeHarness(available: 50, enabled: false)
        await h.scheduler.tick(now: now)
        XCTAssertTrue(h.cleaner.cleanedKinds.isEmpty)
        XCTAssertNil(h.settings.lastLowDiskClean)
    }

    func testDoesNothingWhenSpaceIsFine() async {
        let h = makeHarness(available: 500)
        await h.scheduler.tick(now: now)
        XCTAssertTrue(h.cleaner.cleanedKinds.isEmpty)
    }

    /// Doesn't wait for builds: cleans right away, sparing what they use.
    func testCleansDuringBuildsSparingFoldersInUse() async {
        let inUse: Set<String> = ["/Users/me/Library/Developer/XcodeBuildMCP/workspaces/wt-1/DerivedData"]
        let h = makeHarness(available: 50, builds: FakeBuildDetector(builds: [FakeBuildDetector.sampleBuild],
                                                                     paths: inUse))
        await h.scheduler.tick(now: now)
        XCTAssertEqual(h.cleaner.cleanedKinds, [.directory(path: "~/Library/Developer/Xcode/DerivedData")])
        XCTAssertEqual(h.cleaner.sparedPaths, [inUse])
        XCTAssertEqual(h.settings.lastLowDiskClean, now)
    }

    func testRetriesNextTickWhenBuildsCantBeRead() async {
        let h = makeHarness(available: 50, builds: FakeBuildDetector(paths: nil))
        await h.scheduler.tick(now: now)
        XCTAssertTrue(h.cleaner.cleanedKinds.isEmpty)
        XCTAssertNil(h.settings.lastLowDiskClean)
    }

    func testDoesNotRepeatWithinCooldown() async {
        let h = makeHarness(available: 50)
        await h.scheduler.tick(now: now)
        await h.scheduler.tick(now: now.addingTimeInterval(60))
        XCTAssertEqual(h.cleaner.cleanedKinds.count, 1)
        await h.scheduler.tick(now: now.addingTimeInterval(LowDiskMath.cooldown))
        XCTAssertEqual(h.cleaner.cleanedKinds.count, 2)
    }

    func testViewModelReportsLowDisk() {
        let h = makeHarness(available: 50)
        XCTAssertEqual(h.vm.diskSpace, DiskSpace(availableBytes: 50, totalBytes: 1000))
        XCTAssertTrue(h.vm.isDiskSpaceLow)
    }
}
