import SwiftUI

struct ScoringInfoModal: View {
    var isQuickGame: Bool = false
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Card
            VStack(spacing: 0) {
                Text("Keeping Score")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.top, 28)
                    .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 23) {
                    infoSection(
                        title: isQuickGame ? "You're the Scorer" : "Everyone Can Score",
                        body: isQuickGame
                            ? "You enter scores for all players in your group. Score each player hole by hole as you play."
                            : "Any player in the group can enter and edit scores — no designated scorer needed."
                    )
                    infoSection(
                        title: "Edit Any Hole",
                        body: "Tap any scored hole to make corrections at any time."
                    )
                    infoSection(
                        title: "Live Sync",
                        body: "Scores and skins sync across all groups in real time. Works offline too."
                    )
                    infoSection(
                        title: "Pending & Final Results",
                        body: "Results update as each group finishes. Final results appear when all groups complete 18."
                    )
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)

                Button {
                    onDismiss()
                } label: {
                    Text("Ok Got it")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 13)
                                .fill(.black)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(
                RoundedRectangle(cornerRadius: 29)
                    .fill(.white)
            )
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func infoSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
            Text(body)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color(hexString: "#3E3E3E"))
                .lineSpacing(5)
        }
    }
}

#if DEBUG
#Preview {
    ScoringInfoModal(onDismiss: {})
}
#endif
