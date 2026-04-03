import Foundation

/// Centralises app-level navigation state driven by deep links.
/// Injected as an EnvironmentObject from CarryApp into the view hierarchy.
class AppRouter: ObservableObject {
    /// Non-nil while a group-invite deep link is waiting to be consumed by MainTabView.
    @Published var pendingGroupInvite: ParsedInvite? = nil

    // MARK: - Debug Menu Triggers

    /// Set to true from DebugMenuView; MainTabView watches and resets skinGameGroups to demo data.
    @Published var debugResetGroups: Bool = false

    /// Set to true from DebugMenuView; MainTabView watches and clears all skinGameGroups.
    @Published var debugClearGroups: Bool = false

    /// Set to true from DebugMenuView; GroupsListView watches and shows the "Play again?" recurring prompt.
    @Published var debugShowRecurringPrompt: Bool = false

    /// Set to true from DebugMenuView; GroupsListView watches and shows the quick game limit alert.
    @Published var debugShowQuickGameLimit: Bool = false

    /// Set to true from DebugMenuView; HomeView watches and shows the guest claim picker sheet.
    @Published var debugShowGuestClaim: Bool = false

    /// Set to true from DebugMenuView; shows the Create Group card overlay.
    @Published var debugShowCreateGroupCard: Bool = false

    /// Set to true from DebugMenuView; opens first group and shows invite share sheet.
    @Published var debugShowInviteSheet: Bool = false

    /// Set to true after accepting a group invite; MainTabView watches and reloads groups.
    @Published var shouldRefreshGroups: Bool = false

    /// Navigate to a specific tab after an action (e.g. accepting invite → Games tab).
    @Published var navigateToTab: String? = nil

    /// Set when a "round started" push is tapped — opens the group's scorecard.
    @Published var pendingRoundGroupId: UUID? = nil

}
