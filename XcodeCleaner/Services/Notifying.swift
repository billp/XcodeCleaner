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
