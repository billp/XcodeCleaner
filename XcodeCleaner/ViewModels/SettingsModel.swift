import Foundation
import ServiceManagement

@MainActor
@Observable
final class SettingsModel {
    private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return defaults.bool(forKey: "xclean.launchAtLogin")
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                defaults.set(newValue, forKey: "xclean.launchAtLogin")
            }
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Best-effort; persists intent. The app re-registers on launch.
            }
        }
    }

    var schedulingEnabled: Bool {
        get {
            access(keyPath: \.schedulingEnabled)
            return defaults.bool(forKey: "xclean.schedulingEnabled")
        }
        set {
            withMutation(keyPath: \.schedulingEnabled) {
                defaults.set(newValue, forKey: "xclean.schedulingEnabled")
            }
        }
    }

    var scheduleWeekday: Int {
        get {
            access(keyPath: \.scheduleWeekday)
            return defaults.object(forKey: "xclean.scheduleWeekday") as? Int ?? 6
        }
        set {
            withMutation(keyPath: \.scheduleWeekday) {
                defaults.set(newValue, forKey: "xclean.scheduleWeekday")
            }
        }
    }

    var scheduleHour: Int {
        get {
            access(keyPath: \.scheduleHour)
            return defaults.object(forKey: "xclean.scheduleHour") as? Int ?? 2
        }
        set {
            withMutation(keyPath: \.scheduleHour) {
                defaults.set(newValue, forKey: "xclean.scheduleHour")
            }
        }
    }

    var scheduleMinute: Int {
        get {
            access(keyPath: \.scheduleMinute)
            return defaults.object(forKey: "xclean.scheduleMinute") as? Int ?? 0
        }
        set {
            withMutation(keyPath: \.scheduleMinute) {
                defaults.set(newValue, forKey: "xclean.scheduleMinute")
            }
        }
    }

    var enabledTargetNames: Set<String> {
        get {
            access(keyPath: \.enabledTargetNames)
            guard let data = defaults.data(forKey: "xclean.enabledTargetNames"),
                  let array = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return Set(array)
        }
        set {
            withMutation(keyPath: \.enabledTargetNames) {
                let array = newValue.sorted()
                let data = (try? JSONEncoder().encode(array)) ?? Data()
                defaults.set(data, forKey: "xclean.enabledTargetNames")
            }
        }
    }

    var lastScheduledClean: Date? {
        get {
            access(keyPath: \.lastScheduledClean)
            return defaults.object(forKey: "xclean.lastScheduledClean") as? Date
        }
        set {
            withMutation(keyPath: \.lastScheduledClean) {
                defaults.set(newValue, forKey: "xclean.lastScheduledClean")
            }
        }
    }

    private static let runFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d 'at' h:mm a"
        return f
    }()

    var lastRunText: String? {
        access(keyPath: \.lastScheduledClean)
        guard let date = lastScheduledClean else { return nil }
        return Self.runFormatter.string(from: date)
    }

    var nextRunText: String? {
        access(keyPath: \.nextRunText)
        guard schedulingEnabled else { return nil }
        let cal = Calendar.current
        let now = Date()
        let next = cal.nextDate(
            after: now.addingTimeInterval(-60),
            matching: DateComponents(hour: scheduleHour, minute: scheduleMinute, weekday: scheduleWeekday),
            matchingPolicy: .nextTime
        )
        guard let next else { return nil }
        return Self.runFormatter.string(from: next)
    }
}
