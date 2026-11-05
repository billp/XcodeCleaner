import Foundation
import UserNotifications

protocol Notifying: Sendable {
    func requestAuthorization() async
    func notifyCleanFinished(targetCount: Int, reclaimedBytes: Int64, trigger: AutoCleanTrigger) async
}

struct UserNotifier: Notifying {
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    func notifyCleanFinished(targetCount: Int, reclaimedBytes: Int64, trigger: AutoCleanTrigger) async {
        let content = UNMutableNotificationContent()
        content.title = "Xcode Cleaner"
        let size = ByteCountFormatter.string(fromByteCount: reclaimedBytes, countStyle: .file)
        let caches = targetCount == 1 ? "cache" : "caches"
        let freed = "freed \(size) across \(targetCount) \(caches)."
        switch trigger {
        case .scheduled:
            content.body = "Scheduled clean finished — \(freed)"
        case .lowDisk:
            content.body = "Disk space was low — automatic clean \(freed)"
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
