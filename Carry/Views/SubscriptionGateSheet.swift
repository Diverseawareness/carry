import SwiftUI

/// Half-detent sheet presented to LAPSED users (storeService.hadPremium == true
/// && storeService.isPremium == false) when they enter a Skins Group or Quick
/// Game detail screen they no longer have access to.
///
/// UX intent: rather than a centered empty-state that hides the user's actual
/// data, this sheet slides up from the bottom at ~55% screen height. The user
/// can see their real group/round behind it (non-interactive), which makes
/// the value of subscribing concrete instead of abstract.
///
/// Dismiss behavior:
/// - Swipe down → onDismiss fires → caller bounces back to Games tab. The
///   swipe IS the "not now" affordance; no separate Cancel button needed.
/// - Tap Subscribe → presents the PaywallView; on successful purchase,
///   `storeService.isPremium` flips true and the parent un-presents the sheet,
///   leaving the user on the now-unlocked detail screen.
///
/// First-time users (hadPremium == false) do NOT see this sheet — they get
/// the existing centered empty-state with the trial pitch. Reasoning: a
/// faded empty tee sheet behind a gate tells a brand-new user nothing useful.
struct SubscriptionGateSheet: View {
    /// Tapped when the user taps the primary CTA. The caller is responsible
    /// for presenting the PaywallView. We don't present it here so the sheet
    /// only owns its own surface — keeps the sheet → paywall transition
    /// fully under the parent's control.
    var onSubscribe: () -> Void

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
                Text("Subscribe to Carry")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Subscribe to start games, invite players, and keep your leaderboard going.")
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
