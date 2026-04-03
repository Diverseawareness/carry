import Foundation
import UIKit
import UserNotifications

/// Handles local + push notifications for tee time reminders, game alerts, and invites.
@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    // MARK: - Permission & Registration

    /// Request notification permission and register for remote (push) notifications.
    func requestPermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            #if DEBUG
            if let error {
                print("[Notifications] Permission error: \(error)")
            }
            print("[Notifications] Permission granted: \(granted)")
            #endif
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    /// Legacy — calls requestPermissionAndRegister.
    func requestPermission() {
        requestPermissionAndRegister()
    }

    /// Save device token to Supabase profiles table.
    func saveDeviceToken(_ token: String) async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            try await SupabaseManager.shared.client.from("profiles")
                .update(["device_token": token])
                .eq("id", value: session.user.id.uuidString)
                .execute()
            #if DEBUG
            print("[Push] Device token saved to Supabase")
            #endif
        } catch {
            #if DEBUG
            print("[Push] Failed to save device token: \(error)")
            #endif
        }
    }

    // MARK: - Creator Tee Time Reminder

    /// Schedules a local notification 5 minutes before the tee time.
    /// Call this whenever a tee time is set or changed.
    func scheduleTeeTimeReminder(groupId: UUID, groupName: String, teeTime: Date) {
        // Remove any existing reminder for this group first
        removeTeeTimeReminder(groupId: groupId)

        let fireDate = teeTime.addingTimeInterval(-5 * 60) // 5 min before
        guard fireDate > Date() else { return } // Don't schedule if already past

        let content = UNMutableNotificationContent()
        content.title = "Tee time in 5 minutes"
        content.body = "Start \(groupName) so your players can join the scorecard."
        content.sound = .default
        content.userInfo = ["groupId": groupId.uuidString, "type": "teeTimeReminder"]

        let interval = fireDate.timeIntervalSinceNow
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let request = UNNotificationRequest(
            identifier: "teeTime-\(groupId.uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error {
                print("[Notifications] Failed to schedule tee time reminder: \(error)")
            } else {
                print("[Notifications] Scheduled reminder for \(groupName) at \(fireDate)")
            }
            #endif
        }
    }

    /// Removes a scheduled tee time reminder for a group.
    func removeTeeTimeReminder(groupId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["teeTime-\(groupId.uuidString)"]
        )
    }

    // MARK: - Cross-Group Skin Won Notification

    /// Sends a local notification when a player from another group wins a skin.
    /// Triggered by the polling timer detecting a new skin win from Supabase data.
    func notifySkinWon(playerName: String, holeNum: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Skin Won \u{2014} Hole \(holeNum)"
        content.body = "\(playerName) won a skin on Hole \(holeNum)"
        content.sound = .default
        content.userInfo = ["type": "skinWon", "holeNum": holeNum]

        // Fire immediately (1 second delay required by iOS)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "skinWon-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error {
                print("[Notifications] Failed to send skin won: \(error)")
            }
            #endif
        }
    }

    // MARK: - Game Started Notification

    /// Sends a local notification that the game is live (for players on this device).
    /// In production, this would be a push notification via Supabase to all group members.
    func notifyGameStarted(groupName: String, courseName: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(groupName) is live"
        content.body = "Open your scorecard"
        content.sound = .default
        content.userInfo = ["type": "gameStarted"]

        // Fire immediately (1 second delay required by iOS)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "gameStarted-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error {
                print("[Notifications] Failed to send game started: \(error)")
            }
            #endif
        }
    }
}
