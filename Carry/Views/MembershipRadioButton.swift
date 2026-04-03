import SwiftUI

struct MembershipRadioButton: View {
    let label: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.textPrimary : Color.borderLight, lineWidth: isSelected ? 2 : 1.5)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Color.textPrimary)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.carry.bodySemibold)
                        .foregroundColor(Color.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(Color.textTertiary)
                }

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? Color.bgSecondary : .white))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.textPrimary : Color.borderLight, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
