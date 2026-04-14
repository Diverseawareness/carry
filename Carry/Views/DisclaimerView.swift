import SwiftUI

/// Full-screen disclaimer shown once during first launch, after onboarding.
/// Explains that Carry is a scorekeeper only — no real money flows through the app.
/// Persists acceptance via UserDefaults so it never shows again.
struct DisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Alert icon
            Image("disclaimer-alert")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 80, height: 80)
                .padding(.bottom, 24)

            // Headline
            Text("Carry is a Scorekeeper")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 32)

            // Bullet points
            VStack(alignment: .leading, spacing: 20) {
                bulletRow(
                    icon: "xmark.circle.fill",
                    color: Color(hexString: "#BCF0B5"),
                    text: "Dollar amounts are for scorekeeping and calculating winnings only"
                )
                bulletRow(
                    icon: "xmark.circle.fill",
                    color: Color(hexString: "#BCF0B5"),
                    text: "No real money is processed, held, or transferred through Carry"
                )
                bulletRow(
                    icon: "xmark.circle.fill",
                    color: Color(hexString: "#BCF0B5"),
                    text: "Players settle up independently and are responsible for complying with local laws"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            // Accept button
            Button {
                UserDefaults.standard.set(true, forKey: "disclaimerAccepted")
                onAccept()
            } label: {
                Text("I Understand")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.textPrimary)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Legal links
            HStack(spacing: 4) {
                Link("Terms of Service", destination: URL(string: "https://carryapp.site/terms.html")!)
                Text("and")
                    .foregroundColor(Color.textSecondary)
                Link("Privacy Policy", destination: URL(string: "https://carryapp.site/privacy.html")!)
            }
            .font(.system(size: 13))
            .foregroundColor(Color.textTertiary)
            .padding(.bottom, 40)
        }
        .background(Color.white.ignoresSafeArea())
    }

    private func bulletRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
