import SwiftUI

/// Wrapper that ensures fresh data is passed each time the sheet opens.
struct GuestClaimSheet: View {
    let profiles: [ProfileDTO]
    let groupName: String
    let onClaim: (UUID) -> Void
    let onSkip: () -> Void

    var body: some View {
        GuestClaimView(guests: profiles, groupName: groupName, onClaim: onClaim, onSkip: onSkip)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}

/// "Are you one of these players?" picker — matches scorer picker sheet pattern.
struct GuestClaimView: View {
    let guests: [ProfileDTO]
    let groupName: String
    let onClaim: (UUID) -> Void
    let onSkip: () -> Void

    @State private var selectedId: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            if guests.isEmpty {
                Spacer()
                Text("No players to claim")
                    .font(.carry.bodyLG)
                    .foregroundColor(Color.textTertiary)
                Spacer()
                Button { onSkip() } label: {
                    Text("Continue")
                        .font(.carry.bodySMSemibold)
                        .foregroundColor(Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            } else {
                // Header — matches scorer picker
                Text("Are you one of these players?")
                    .font(.carry.labelBold)
                    .foregroundColor(Color.textPrimary)
                    .padding(.top, 40)
                    .padding(.bottom, 6)

                Text("Claim your profile to see your round history.")
                    .font(.carry.captionLG)
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                // Player list — matches scorer picker rows
                ForEach(guests) { guest in
                    Button {
                        selectedId = guest.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onClaim(guest.id)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            // Avatar
                            ZStack {
                                Circle()
                                    .fill(Color(hexString: "#BCF0B5"))
                                Circle()
                                    .strokeBorder(Color(hexString: "#A3E09C"), lineWidth: 1.5)
                                Text(guest.initials)
                                    .font(.custom("ANDONESI-Regular", size: 17))
                                    .foregroundColor(Color(hexString: "#064102"))
                            }
                            .frame(width: 43, height: 43)

                            // Name + handicap
                            VStack(alignment: .leading, spacing: 2) {
                                Text(guest.displayName)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundColor(Color.textPrimary)
                                    .lineLimit(1)

                                Text(String(format: "%.1f", guest.handicap))
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.textSecondary)
                            }

                            Spacer()

                            // Radio circle
                            if selectedId == guest.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(Color.textPrimary)
                            } else {
                                Circle()
                                    .strokeBorder(Color(hexString: "#DDDDDD"), lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if guest.id != guests.last?.id {
                        Rectangle()
                            .fill(Color.bgPrimary)
                            .frame(height: 1)
                            .padding(.leading, 86)
                    }
                }

                Spacer()

                // Skip
                Button {
                    onSkip()
                } label: {
                    Text("None of these")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.textPrimary))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
}
