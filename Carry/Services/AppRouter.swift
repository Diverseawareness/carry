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
    @Published var debugShowQuickGameLimit: Bool = false
    @Published var debugShowGuestClaim: Bool = false
    @Published var debugShowCreateGroupCard: Bool = false
    @Published var debugShowInviteSheet: Bool = false
    #endif

    /// Set to true after accepting a group invite; MainTabView watches and reloads groups.
    @Published var shouldRefreshGroups: Bool = false

    /// Navigate to a specific tab after an action (e.g. accepting invite → Games tab).
    @Published var navigateToTab: String? = nil

    /// Set when a "round started" push is tapped — opens the group's scorecard.
    @Published var pendingRoundGroupId: UUID? = nil

}
