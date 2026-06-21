import XCTest
@testable import XcodeCleaner

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private func makeSuite() -> UserDefaults {
        let name = "xclean.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    func testDefaultsAreSensible() {
        let settings = SettingsViewModel(userDefaults: makeSuite())
        XCTAssertFalse(settings.launchAtLoginDesired)
        XCTAssertFalse(settings.schedulingEnabled)
        XCTAssertEqual(settings.scheduleWeekday, 6)
        XCTAssertEqual(settings.scheduleHour, 2)
        XCTAssertEqual(settings.scheduleMinute, 0)
        XCTAssertTrue(settings.enabledTargetNames.isEmpty)
    }

    func testEnabledTargetNamesRoundTrips() {
        let suite = makeSuite()
        let settings = SettingsViewModel(userDefaults: suite)
        settings.enabledTargetNames = ["Xcode DerivedData", "SwiftPM cache"]
        // Read back from a fresh instance on the same suite
        let reread = SettingsViewModel(userDefaults: suite)
        XCTAssertEqual(reread.enabledTargetNames, ["Xcode DerivedData", "SwiftPM cache"])
    }

    func testAllScalarSettingsRoundTrip() {
        let suite = makeSuite()
        let settings = SettingsViewModel(userDefaults: suite)
        settings.launchAtLogin = true
        settings.schedulingEnabled = true
        settings.scheduleWeekday = 3
        settings.scheduleHour = 5
        settings.scheduleMinute = 30
        let reread = SettingsViewModel(userDefaults: suite)
        XCTAssertTrue(reread.launchAtLoginDesired)
        XCTAssertTrue(reread.schedulingEnabled)
        XCTAssertEqual(reread.scheduleWeekday, 3)
        XCTAssertEqual(reread.scheduleHour, 5)
        XCTAssertEqual(reread.scheduleMinute, 30)
    }

    func testLastScheduledCleanPersistsAcrossInstances() {
        let name = "xclean.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        SettingsViewModel(userDefaults: suite).lastScheduledClean = date
        let reloaded = SettingsViewModel(userDefaults: suite).lastScheduledClean
        XCTAssertEqual(reloaded?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 1)
    }

    func testLastRunTextNilWhenNeverRun() {
        let name = "xclean.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        XCTAssertNil(SettingsViewModel(userDefaults: suite).lastRunText)
    }

    func testLastRunTextReflectsMutation() {
        let name = "xclean.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        let s = SettingsViewModel(userDefaults: suite)
        XCTAssertNil(s.lastRunText)
        s.lastScheduledClean = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNotNil(s.lastRunText)
    }

    func testRequestsAuthOnlyWhenSchedulingEnabled() async {
        let settings = SettingsViewModel(userDefaults: makeSuite())
        let notifier = FakeNotifier()

        settings.schedulingEnabled = false
        await settings.requestSchedulingAuthorizationIfNeeded(notifier: notifier)
        XCTAssertEqual(notifier.authorizationRequests, 0)

        settings.schedulingEnabled = true
        await settings.requestSchedulingAuthorizationIfNeeded(notifier: notifier)
        XCTAssertEqual(notifier.authorizationRequests, 1)
    }
}
