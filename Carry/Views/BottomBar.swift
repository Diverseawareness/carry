import SwiftUI

struct BottomBar: View {
    let hole: Hole
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("Hole \(hole.num) · Par \(hole.par)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "1A1A1A"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "FAFAFA"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "EBEBEB"), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(height: 56)
    }
}
