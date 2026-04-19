import SwiftUI

/// Wraps a Button so it renders normally for premium users and as a
/// visibly-locked control for free users. Free users see the label dimmed
/// with a small crown badge; tapping opens the paywall with a contextual
/// trigger instead of invoking the action.
///
/// Usage:
/// ```
/// PremiumGatedButton(trigger: .startRound, action: { startRound() }) {
///     Text("Start Round")
///         .font(.carry.bodyLGBold)
///         .frame(maxWidth: .infinity, minHeight: 56)
///         .background(Color.deepNavy)
///         .foregroundColor(.white)
/// }
/// ```
///
/// The paywall sheet is presented from this view via `.sheet`, so no
/// parent plumbing is required. Callers who already host a paywall sheet
/// should use `.manualPaywall` to opt out of auto-presenting and handle
/// the trigger themselves (see `onGatedTap` parameter).
struct PremiumGatedButton<Label: View>: View {
    @EnvironmentObject var storeService: StoreService

    let trigger: PaywallTrigger
    let action: () -> Void
    let label: () -> Label

    /// Optional callback invoked when a free user taps the button. When set,
    /// the paywall sheet is NOT presented automatically — the caller is
    /// responsible for opening one. Useful when the caller manages its own
    /// `showPaywall` state to avoid stacking sheets.
    var onGatedTap: ((PaywallTrigger) -> Void)? = nil

    @State private var showPaywall = false

    var body: some View {
        Button {
            if storeService.isPremium {
                action()
            } else if let onGatedTap {
                onGatedTap(trigger)
            } else {
                showPaywall = true
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                label()
                    .opacity(storeService.isPremium ? 1.0 : 0.5)

                if !storeService.isPremium {
                    Image("premium-crown")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundColor(Color.goldAccent)
                        .padding(6)
                        .background(Circle().fill(Color.white))
                        .offset(x: 4, y: -4)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(storeService.isPremium ? "" : "Requires Premium subscription")
        .sheet(isPresented: $showPaywall) {
            PaywallView(trigger: trigger)
                .environmentObject(storeService)
        }
    }

    /// Matches the visible label when possible. SwiftUI can't introspect
    /// the label content, so we compose a sensible default based on the
    /// trigger for VoiceOver users.
    private var accessibilityLabel: String {
        switch trigger {
        case .startRound:          return "Start Round"
        case .createGroup:         return "Create Skins Group"
        case .scoreRound:          return "Score Round"
        case .manageGroup:         return "Manage Group"
        case .quickGameLimit:      return "Quick Game"
        case .allTimeLeaderboard:  return "All-time Leaderboard"
        case .general:             return "Premium feature"
        }
    }
}
