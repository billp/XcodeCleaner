import Foundation

enum ScheduleMath {
    static let buildProcessNames: Set<String> = [
        "xcodebuild", "swift", "swiftc", "clang", "clang++", "ld", "swift-frontend",
    ]

    /// True if the basename of `comm` (e.g. "/usr/bin/xcodebuild" → "xcodebuild")
    /// is in `buildProcessNames`.
    static func isBuildProcess(_ comm: String) -> Bool {
        let name = (comm as NSString).lastPathComponent
        return buildProcessNames.contains(name)
    }

    /// True if `now` matches the configured weekday/hour/minute AND `lastFired`
    /// is nil or before today's slot (prevents double-firing within the same minute).
    static func shouldFire(now: Date, weekday: Int, hour: Int, minute: Int, lastFired: Date?) -> Bool {
        let cal = Calendar.current
        let nowWeekday = cal.component(.weekday, from: now)
        let nowHour = cal.component(.hour, from: now)
        let nowMinute = cal.component(.minute, from: now)
        guard nowWeekday == weekday, nowHour == hour, nowMinute == minute else { return false }
        guard let lastFired else { return true }
        // Build today's slot start and ensure lastFired is before it.
        let slot = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        return lastFired < slot
    }

    /// `from + 1 hour`, with seconds and minutes zeroed (truncates to the top of the hour).
    static func postponedFireTime(from: Date) -> Date {
        let cal = Calendar.current
        let plusHour = from.addingTimeInterval(60 * 60)
        return cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: plusHour)) ?? plusHour
    }

    /// `originalFire + 24 hours`.
    static func giveUpTime(originalFire: Date) -> Date {
        originalFire.addingTimeInterval(24 * 60 * 60)
    }

    /// The most recent scheduled slot at or before `now`.
    /// Returns `nil` if the calendar cannot find a match (extremely unlikely).
    static func lastScheduledSlot(
        before now: Date, weekday: Int, hour: Int, minute: Int
    ) -> Date? {
        let cal = Calendar.current
        let comps = DateComponents(hour: hour, minute: minute, weekday: weekday)
        return cal.nextDate(
            after: now.addingTimeInterval(1),
            matching: comps,
            matchingPolicy: .nextTime,
            direction: .backward
        )
    }
}
