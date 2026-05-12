import SwiftUI

/// Post-demo "Want a weekly game like this?" sheet.
///
/// Presented by `RoundCompleteView` when the round is a demo round
/// (`viewModel.config.isDemo == true`). REPLACES the standard convert-QG-to-SG
/// sheet because the demo's fictional opponents (Ryan/Mike/Lisa) cannot be
/// carried into a real recurring group — they were ephemeral by design.
///
/// "Yes" path: dismisses the demo and routes the user into the new-Skins-Group
/// creation flow with the user as solo host + weekly recurrence pre-selected.
/// "No" path: just dismisses the demo. Either way the demo card never re-renders.
struct DemoConvertSheet: View {
    let displayName: String?
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.textTertiary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Hero icon
            ZStack {
                Circle()
                    .fill(Color.successGreen.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(Color.successGreen)
            }
            .padding(.top, 28)

            // Title + body
            Text("Want a weekly game like this?")
                .font(.carry.sheetTitle)
                .foregroundColor(Color.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .padding(.horizontal, 24)

            Text("We'll set up your own group with you as the host. Invite friends to play next week, every week.")
                .font(.carry.body)
                .foregroundColor(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 24)

            // Buttons
            VStack(spacing: 12) {
                Button(action: onAccept) {
                    HStack(spacing: 6) {
                        Text("Yes, set it up")
                            .font(.carry.bodyLGBold)
                            .foregroundColor(.white)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.pureBlack))
                }
                .buttonStyle(.plain)

                Button(action: onDecline) {
                    Text("No thanks")
                        .font(.carry.bodyLG)
                        .foregroundColor(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color.bgPrimary.ignoresSafeArea(edges: .bottom))
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}
