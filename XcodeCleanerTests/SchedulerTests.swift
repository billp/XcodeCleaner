import XCTest
@testable import XcodeCleaner

@MainActor
final class SchedulerTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func makeFireDate() -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 26  // Friday
        comps.hour = 2; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone.current
        return cal.date(from: comps)!
    }

    private func makeSuite() -> UserDefaults {
        let name = "xclean.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    /// Polls until `cond` is true or the timeout elapses (ViewModel mutates state from an async Task).
    private func waitUntil(timeout: TimeInterval = 2.0, _ cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testTickDoesNothingWhenSchedulingDisabled() async {
        let settings = SettingsModel(userDefaults: makeSuite())
        settings.schedulingEnabled = false
        let cleaner = FakeCleaner(result: .success(()))
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: true))
        let scheduler = Scheduler(vm: vm, settings: settings,
                                  runner: FakeCommandRunner(status: 0, stdout: Data("bash\n".utf8)))
        await scheduler.tick(now: makeFireDate())
        XCTAssertTrue(cleaner.cleanedKinds.isEmpty)
    }

    func testTickPostponesWhenBuildProcessRunning() async {
        let settings = SettingsModel(userDefaults: makeSuite())
        settings.schedulingEnabled = true
        settings.enabledTargetNames = ["Xcode DerivedData"]
        let cleaner = FakeCleaner(result: .success(()))
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: true))
        let runner = FakeCommandRunner(status: 0, stdout: Data("xcodebuild\n".utf8))
        let scheduler = Scheduler(vm: vm, settings: settings, runner: runner)
        let fire = makeFireDate()
        await scheduler.tick(now: fire)
        XCTAssertTrue(cleaner.cleanedKinds.isEmpty)
        XCTAssertNotNil(scheduler.pendingFire)
    }

    func testTickFiresWhenNoBuildProcessRunning() async {
        let settings = SettingsModel(userDefaults: makeSuite())
        settings.schedulingEnabled = true
        settings.enabledTargetNames = ["Xcode DerivedData"]
        let cleaner = FakeCleaner(result: .success(()))
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: true))
        let runner = FakeCommandRunner(status: 0, stdout: Data("bash\ngoogle-chrome\n".utf8))
        let scheduler = Scheduler(vm: vm, settings: settings, runner: runner, notifier: FakeNotifier())
        let fire = makeFireDate()
        await scheduler.tick(now: fire)
        await waitUntil { cleaner.cleanedKinds.count == 1 }
        XCTAssertEqual(cleaner.cleanedKinds, [.directory(path: "~/Library/Developer/Xcode/DerivedData")])
        XCTAssertNotNil(scheduler.lastFired)
        XCTAssertNil(scheduler.pendingFire)
    }

    func testTickGivesUpAfter24Hours() async {
        let settings = SettingsModel(userDefaults: makeSuite())
        settings.schedulingEnabled = true
        settings.enabledTargetNames = ["Xcode DerivedData"]
        let cleaner = FakeCleaner(result: .success(()))
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: true))
        let runner = FakeCommandRunner(status: 0, stdout: Data("xcodebuild\n".utf8))
        let scheduler = Scheduler(vm: vm, settings: settings, runner: runner)
        let original = makeFireDate()
        scheduler.originalFire = original
        scheduler.pendingFire = original
        // Now is 25 hours after original — past the 24h give-up window.
        let now = original.addingTimeInterval(25 * 60 * 60)
        await scheduler.tick(now: now)
        XCTAssertTrue(cleaner.cleanedKinds.isEmpty)
        XCTAssertNil(scheduler.pendingFire)
        XCTAssertNil(scheduler.originalFire)
    }

    func testTickRecordsLastCleanAndNotifies() async {
        let settings = SettingsModel(userDefaults: makeSuite())
        settings.schedulingEnabled = true
        settings.enabledTargetNames = ["Xcode DerivedData"]
        let vm = CleanerViewModel(scanner: FakeScanner(results: [.success(1000), .success(0)]),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: false))
        let notifier = FakeNotifier()
        let scheduler = Scheduler(vm: vm, settings: settings,
                                  runner: FakeCommandRunner(status: 0, stdout: Data("bash\n".utf8)),
                                  notifier: notifier)
        let fire = makeFireDate()
        await scheduler.tick(now: fire)
        XCTAssertEqual(settings.lastScheduledClean, fire)
        XCTAssertEqual(notifier.finishedCalls.count, 1)
        XCTAssertEqual(notifier.finishedCalls.first?.count, 1)
    }

    func testTickWithNoTargetsDoesNotNotify() async {
        let settings = SettingsModel(userDefaults: makeSuite())
        settings.schedulingEnabled = true
        settings.enabledTargetNames = []    // no targets enabled
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: false))
        let notifier = FakeNotifier()
        let scheduler = Scheduler(vm: vm, settings: settings,
                                  runner: FakeCommandRunner(status: 0, stdout: Data("bash\n".utf8)),
                                  notifier: notifier)
        let fire = makeFireDate()
        await scheduler.tick(now: fire)
        XCTAssertEqual(settings.lastScheduledClean, fire)
        XCTAssertTrue(notifier.finishedCalls.isEmpty)
    }

    func testTickPostponesThenFiresWhenBuildFinishes() async {
        let settings = SettingsModel(userDefaults: makeSuite())
        settings.schedulingEnabled = true
        settings.enabledTargetNames = ["Xcode DerivedData"]
        let cleaner = FakeCleaner(result: .success(()))
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: cleaner,
                                  availability: FakeAvailability(existsResult: true))
        // First ps call returns a build process; second returns no build process.
        let runner = FakeCommandRunner(responses: [
            .init(status: 0, stdout: Data("xcodebuild\n".utf8), stderr: Data()),
            .init(status: 0, stdout: Data("bash\n".utf8), stderr: Data()),
        ])
        let scheduler = Scheduler(vm: vm, settings: settings, runner: runner)
        let fire = makeFireDate()

        // First tick: build is running → postpone.
        await scheduler.tick(now: fire)
        XCTAssertTrue(cleaner.cleanedKinds.isEmpty)
        XCTAssertNotNil(scheduler.pendingFire)
        XCTAssertNotNil(scheduler.originalFire)

        // Advance to the postponed slot: build is now finished → fire.
        let postponed = scheduler.pendingFire!
        await scheduler.tick(now: postponed)
        await waitUntil { cleaner.cleanedKinds.count == 1 }
        XCTAssertEqual(cleaner.cleanedKinds, [.directory(path: "~/Library/Developer/Xcode/DerivedData")])
        XCTAssertNotNil(scheduler.lastFired)
        XCTAssertNil(scheduler.pendingFire)
        XCTAssertNil(scheduler.originalFire)
    }
}
