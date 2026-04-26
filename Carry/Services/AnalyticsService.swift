import Foundation
import PostHog

/// Centralized analytics tracking via PostHog.
/// All event names and properties are defined here for consistency.
enum Analytics {

    // MARK: - Round Events

    static func roundStarted(groupName: String, playerCount: Int, buyIn: Int, courseName: String) {
        PostHogSDK.shared.capture("round_started", properties: [
            "group_name": groupName,
            "player_count": playerCount,
            "buy_in": buyIn,
            "course_name": courseName
        ])
    }

    static func roundCompleted(groupName: String, playerCount: Int, buyIn: Int, skinsAwarded: Int) {
        PostHogSDK.shared.capture("round_completed", properties: [
            "group_name": groupName,
            "player_count": playerCount,
            "buy_in": buyIn,
            "skins_awarded": skinsAwarded
        ])
    }

    // MARK: - Group Events

    static func groupCreated(name: String, memberCount: Int, buyIn: Double, hasRecurrence: Bool) {
        PostHogSDK.shared.capture("group_created", properties: [
            "group_name": name,
            "member_count": memberCount,
            "buy_in": buyIn,
            "has_recurrence": hasRecurrence
        ])
    }

    static func groupDeleted() {
        PostHogSDK.shared.capture("group_deleted")
    }

    // MARK: - Invite Events

    static func inviteSent(method: String) {
        PostHogSDK.shared.capture("invite_sent", properties: [
            "method": method  // "search", "sms", "phone"
        ])
    }

    static func inviteAccepted() {
        PostHogSDK.shared.capture("invite_accepted")
    }

    static func inviteDeclined() {
        PostHogSDK.shared.capture("invite_declined")
    }

    // MARK: - Onboarding Events

    static func onboardingCompleted() {
        PostHogSDK.shared.capture("onboarding_completed")
    }

    // MARK: - Email Events

    static func welcomeEmailSent() {
        PostHogSDK.shared.capture("welcome_email_sent")
    }

    static func welcomeEmailFailed(reason: String) {
        PostHogSDK.shared.capture("welcome_email_failed", properties: [
            "reason": reason
        ])
    }

    // MARK: - Scorecard Events

    static func scorecardOpened(groupName: String) {
        PostHogSDK.shared.capture("scorecard_opened", properties: [
            "group_name": groupName
        ])
    }

    static func scoreEntered(holeNum: Int) {
        PostHogSDK.shared.capture("score_entered", properties: [
            "hole_num": holeNum
        ])
    }

    // MARK: - Screen Views (manual)

    static func screenViewed(_ name: String) {
        PostHogSDK.shared.screen(name)
    }
}
