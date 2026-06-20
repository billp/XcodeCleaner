import XCTest
@testable import XcodeCleaner

@MainActor
final class SettingsModelTests: XCTestCase {
    private func makeSuite() -> UserDefaults {
        let name = "xclean.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    func testDefaultsAreSensible() {
        let settings = SettingsModel(userDefaults: makeSuite())
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertFalse(settings.schedulingEnabled)
        XCTAssertEqual(settings.scheduleWeekday, 6)
        XCTAssertEqual(settings.scheduleHour, 2)
        XCTAssertEqual(settings.scheduleMinute, 0)
        XCTAssertTrue(settings.enabledTargetNames.isEmpty)
    }

    func testEnabledTargetNamesRoundTrips() {
        let suite = makeSuite()
        let settings = SettingsModel(userDefaults: suite)
        settings.enabledTargetNames = ["Xcode DerivedData", "SwiftPM cache"]
        // Read back from a fresh instance on the same suite
        let reread = SettingsModel(userDefaults: suite)
        XCTAssertEqual(reread.enabledTargetNames, ["Xcode DerivedData", "SwiftPM cache"])
    }

    func testAllScalarSettingsRoundTrip() {
        let suite = makeSuite()
        let settings = SettingsModel(userDefaults: suite)
        settings.launchAtLogin = true
        settings.schedulingEnabled = true
        settings.scheduleWeekday = 3
        settings.scheduleHour = 5
        settings.scheduleMinute = 30
        let reread = SettingsModel(userDefaults: suite)
        XCTAssertTrue(reread.launchAtLogin)
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
        SettingsModel(userDefaults: suite).lastScheduledClean = date
        let reloaded = SettingsModel(userDefaults: suite).lastScheduledClean
        XCTAssertEqual(reloaded?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 1)
    }

    func testLastRunTextNilWhenNeverRun() {
        let name = "xclean.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        XCTAssertNil(SettingsModel(userDefaults: suite).lastRunText)
    }
}
