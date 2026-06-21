import XCTest
@testable import XcodeCleaner

final class ScheduleMathTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    func testIsBuildProcessMatchesKnownNames() {
        XCTAssertTrue(ScheduleMath.isBuildProcess("xcodebuild"))
        XCTAssertTrue(ScheduleMath.isBuildProcess("/usr/bin/xcodebuild"))
        XCTAssertTrue(ScheduleMath.isBuildProcess("swift-frontend"))
        XCTAssertTrue(ScheduleMath.isBuildProcess("clang"))
        XCTAssertTrue(ScheduleMath.isBuildProcess("clang++"))
        XCTAssertFalse(ScheduleMath.isBuildProcess("Photos"))
        XCTAssertFalse(ScheduleMath.isBuildProcess(""))
    }

    func testShouldFireMatchesExactSlot() {
        // Friday June 26 2026, 02:00:30 local
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 26
        comps.hour = 2; comps.minute = 0; comps.second = 30
        comps.timeZone = TimeZone.current
        let now = cal.date(from: comps)!
        XCTAssertTrue(ScheduleMath.shouldFire(now: now, weekday: 6, hour: 2, minute: 0, lastFired: nil))
    }

    func testShouldFireRespectsLastFired() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 26
        comps.hour = 2; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone.current
        let slot = cal.date(from: comps)!
        let now = slot.addingTimeInterval(30) // 02:00:30, same slot
        XCTAssertFalse(ScheduleMath.shouldFire(now: now, weekday: 6, hour: 2, minute: 0, lastFired: slot))
    }

    func testShouldFireAllowsNextWeekAfterLastFired() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 19  // previous Friday
        comps.hour = 2; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone.current
        let lastFired = cal.date(from: comps)!
        comps.day = 26  // this Friday, same slot
        comps.second = 30
        let now = cal.date(from: comps)!
        XCTAssertTrue(ScheduleMath.shouldFire(now: now, weekday: 6, hour: 2, minute: 0, lastFired: lastFired))
    }

    func testShouldFireIgnoresDifferentWeekday() {
        // Thursday June 25 2026, 02:00:00 local
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25
        comps.hour = 2; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone.current
        let now = cal.date(from: comps)!
        XCTAssertFalse(ScheduleMath.shouldFire(now: now, weekday: 6, hour: 2, minute: 0, lastFired: nil))
    }

    func testPostponedFireTimeAddsHourAndTruncatesMinutes() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 27
        comps.hour = 2; comps.minute = 0; comps.second = 30
        comps.timeZone = TimeZone.current
        let from = cal.date(from: comps)!
        let result = ScheduleMath.postponedFireTime(from: from)
        let resultComps = cal.dateComponents([.hour, .minute, .second], from: result)
        XCTAssertEqual(resultComps.hour, 3)
        XCTAssertEqual(resultComps.minute, 0)
        XCTAssertEqual(resultComps.second, 0)
    }

    func testPostponedFireTimeZeroesNonZeroMinutes() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 27
        comps.hour = 2; comps.minute = 30; comps.second = 45
        comps.timeZone = TimeZone.current
        let from = cal.date(from: comps)!
        let result = ScheduleMath.postponedFireTime(from: from)
        let resultComps = cal.dateComponents([.hour, .minute, .second], from: result)
        XCTAssertEqual(resultComps.hour, 3)
        XCTAssertEqual(resultComps.minute, 0)
        XCTAssertEqual(resultComps.second, 0)
    }

    func testGiveUpTimeIs24HoursLater() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 27
        comps.hour = 2; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone.current
        let original = cal.date(from: comps)!
        let result = ScheduleMath.giveUpTime(originalFire: original)
        XCTAssertEqual(result.timeIntervalSince(original), 24 * 60 * 60, accuracy: 1)
    }
}
