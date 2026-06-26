import Foundation
import UserNotifications

/// Local user notifications for the "you're not tracking" reminder.
@MainActor
public enum Notifier {
    /// Ask for permission to show notifications. Idempotent — the system only
    /// prompts the first time. Call when the user opts in.
    public static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Fire the "not tracking" reminder immediately.
    public static func notifyNotTracking() {
        let content = UNMutableNotificationContent()
        content.title = "Conan"
        content.body = "You've been working without a timer running. Start tracking?"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "conan.not-tracking-reminder",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
