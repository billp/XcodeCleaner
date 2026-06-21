import Foundation
import UserNotifications

protocol Notifying: Sendable {
    func requestAuthorization() async
    func notifyCleanFinished(targetCount: Int, reclaimedBytes: Int64) async
}

struct UserNotifier: Notifying {
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    func notifyCleanFinished(targetCount: Int, reclaimedBytes: Int64) async {
        let content = UNMutableNotificationContent()
        content.title = "Xcode Cleaner"
        let size = ByteCountFormatter.string(fromByteCount: reclaimedBytes, countStyle: .file)
        let caches = targetCount == 1 ? "cache" : "caches"
        content.body = "Scheduled clean finished — freed \(size) across \(targetCount) \(caches)."
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Requests notification authorization at launch when scheduling is already
/// enabled. The Schedule toggle's onChange only fires on a fresh toggle, so a
/// persisted-enabled schedule would otherwise never (re)request authorization.
@MainActor
func requestSchedulingAuthorizationIfNeeded(settings: SettingsModel, notifier: Notifying) async {
    guard settings.schedulingEnabled else { return }
    await notifier.requestAuthorization()
}
