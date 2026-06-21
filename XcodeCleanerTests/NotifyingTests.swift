import XCTest
@testable import XcodeCleaner

@MainActor
final class NotifyingTests: XCTestCase {
    private func makeSuite() -> UserDefaults {
        let name = "xclean.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
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
