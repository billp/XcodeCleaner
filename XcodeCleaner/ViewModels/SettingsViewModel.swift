import Foundation
import ServiceManagement

@MainActor
@Observable
final class SettingsViewModel {
    private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = error.localizedDescription
            }
            defaults.set(newValue, forKey: "xclean.launchAtLogin")
            withMutation(keyPath: \.launchAtLogin) { }
            withMutation(keyPath: \.launchAtLoginDesired) { }
        }
    }

    /// The user's desired state, persisted across launches. Used by
    /// `reconcileLaunchAtLogin` to re-register if the system dropped the
    /// login item. May differ from `launchAtLogin` when registration failed.
    var launchAtLoginDesired: Bool {
        access(keyPath: \.launchAtLoginDesired)
        return defaults.bool(forKey: "xclean.launchAtLogin")
    }

    /// Last error from registering or unregistering the login item, if any.
    var launchAtLoginError: String?

    /// Re-register the login item on launch if the user previously enabled it
    /// but the system dropped it (e.g. after an OS update or app move).
    func reconcileLaunchAtLogin() {
        guard launchAtLoginDesired, SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        withMutation(keyPath: \.launchAtLogin) { }
    }

    /// Requests notification authorization at launch when an automatic clean
    /// (scheduled or low-disk) is already enabled. The toggles' onChange only fires
    /// on a fresh toggle, so a persisted-enabled setting would otherwise never
    /// (re)request authorization.
    func requestSchedulingAuthorizationIfNeeded(notifier: Notifying) async {
        guard schedulingEnabled || lowDiskCleanEnabled else { return }
        await notifier.requestAuthorization()
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

    /// Automatically clean the selected targets when free disk space drops
    /// below `LowDiskMath.threshold`.
    var lowDiskCleanEnabled: Bool {
        get {
            access(keyPath: \.lowDiskCleanEnabled)
            return defaults.bool(forKey: "xclean.lowDiskCleanEnabled")
        }
        set {
            withMutation(keyPath: \.lowDiskCleanEnabled) {
                defaults.set(newValue, forKey: "xclean.lowDiskCleanEnabled")
            }
        }
    }

    /// When the last low-disk clean started; drives the re-run cooldown.
    var lastLowDiskClean: Date? {
        get {
            access(keyPath: \.lastLowDiskClean)
            return defaults.object(forKey: "xclean.lastLowDiskClean") as? Date
        }
        set {
            withMutation(keyPath: \.lastLowDiskClean) {
                defaults.set(newValue, forKey: "xclean.lastLowDiskClean")
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

    var lastLowDiskCleanText: String? {
        guard let date = lastLowDiskClean else { return nil }
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
