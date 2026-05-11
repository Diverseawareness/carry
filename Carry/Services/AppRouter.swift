import Foundation

/// Centralises app-level navigation state driven by deep links.
/// Injected as an EnvironmentObject from CarryApp into the view hierarchy.
class AppRouter: ObservableObject {
    /// Non-nil while a group-invite deep link is waiting to be consumed by MainTabView.
    @Published var pendingGroupInvite: ParsedInvite? = nil

    // MARK: - Debug Menu Triggers (gated so they don't exist in release builds)

    #if DEBUG
    @Published var debugResetGroups: Bool = false
    @Published var debugClearGroups: Bool = false
    @Published var debugShowRecurringPrompt: Bool = false
    @Published var debugShowCreateGroupCard: Bool = false
    @Published var debugShowInviteSheet: Bool = false
    /// Jumps to phase 2 of the convert-setup sheet (Bring Your Crew / QR +
    /// crew list) with a mock SavedGroup so the flow can be reviewed
    /// without playing a full Quick Game.
    @Published var debugShowConvertInviteCrew: Bool = false
    /// Jumps to phase 1 (the "Convert game into a recurring Skins Group"
    /// prompt, Figma `1187:10698`) in isolation for visual review.
    @Published var debugShowConvertPrompt: Bool = false
    /// Simulates the "user scanned a QR from iPhone Camera, installed
    /// Carry, finished onboarding" flow by writing a Carry invite URL to
    /// the clipboard and forcing HomeView to re-check its pasteboard so
    /// the "Open your invite" banner appears. The Debug menu action
    /// populates this from the user's first existing group so the tap
    /// actually completes end-to-end.
    @Published var debugSimulateClipboardInvite: Bool = false
    /// Forces HomeView to present PhoneInviteFinderSheet regardless of
    /// the normal hasURLs/skinGameGroups gates. Useful for visual review
    /// of the modal without needing a clipboard hint.
    @Published var debugShowPhoneInviteFinder: Bool = false
    #endif

    /// Set to true after accepting a group invite; MainTabView watches and reloads groups.
    @Published var shouldRefreshGroups: Bool = false

    /// Navigate to a specific tab after an action (e.g. accepting invite → Games tab).
    @Published var navigateToTab: String? = nil

    /// Set when a "round started" push is tapped — opens the group's scorecard.
    @Published var pendingRoundGroupId: UUID? = nil

    /// Set when "Create Group" is tapped from a Quick Game's final results
    /// while the round was entered via the Home-tab Active Round card.
    /// GroupsListView watches this to fire its convert flow once the user
    /// lands on the Games tab. Cleared by the consumer.
    @Published var pendingConvertGroupId: UUID? = nil

}
