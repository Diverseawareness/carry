import SwiftUI

/// Half-detent sheet presented to any non-subscriber (storeService.isPremium
/// == false) when they enter a Skins Group or Quick Game detail screen.
/// Covers both audiences with one gate experience:
///
///   - Lapsed users (storeService.hadPremium == true): GroupManagerView
///     keeps the tee-time content rendered behind the sheet so they see
///     their real data through the dimmed background — "subscribe to keep
///     your groups going" reads concrete instead of abstract.
///   - First-time invited members (storeService.hadPremium == false): no
///     real data yet, so the sheet sits over a dimmed header. The gate
///     still fires so they don't see broken/empty editing affordances.
///
/// Dismiss behavior:
/// - Swipe down → onDismiss fires → caller bounces back to Games tab. The
///   swipe IS the "not now" affordance; no separate Cancel button needed.
/// - Tap Subscribe → presents the PaywallView; on successful purchase,
///   `storeService.isPremium` flips true and the parent un-presents the sheet,
///   leaving the user on the now-unlocked detail screen.
struct SubscriptionGateSheet: View {
    /// Tapped when the user taps the primary CTA. The caller is responsible
    /// for presenting the PaywallView. We don't present it here so the sheet
    /// only owns its own surface — keeps the sheet → paywall transition
    /// fully under the parent's control.
    var onSubscribe: () -> Void

    /// True if the user has previously been on a subscription (lapsed),
    /// false for first-time invited members who've never started a trial.
    /// Drives the hero + subhero copy: first-timers see the trial pitch
    /// ("Start Your Free Trial" + "Try Carry free for 30 days…") so the
    /// 30-day-free offer is explicit, lapsed users see the subscribe
    /// pitch ("Subscribe to Carry" + "Subscribe to start games…") since
    /// offering them a trial they already used would mislead.
    var hasUsedTrial: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 4)

            // Carry brand glyph in a mint chip. Bell was the original
            // placeholder; the brand mark reads as "Carry asks you to
            // subscribe" instead of generic notification iconography.
            ZStack {
                Circle()
                    .fill(Color.mintLight)
                    .frame(width: 88, height: 88)
                Image("carry-glyph")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
            }

            VStack(spacing: 10) {
                Text(hasUsedTrial ? "Subscribe to Carry" : "Start Your Free Trial")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(hasUsedTrial
                     ? "Subscribe to start games, invite players, and keep your leaderboard going."
                     : "Try Carry free for 30 days. Start games, invite players, and keep your leaderboard going.")
                    .font(.system(size: 15))
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Spacer()

            // Primary CTA. Black-on-white per the Figma; matches the
            // post-trial paywall's "Subscribe" button styling for consistency
            // (lapsed users see the same word twice across two screens →
            // reinforces the action).
            Button { onSubscribe() } label: {
                Text("Subscribe")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.textPrimary)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}
