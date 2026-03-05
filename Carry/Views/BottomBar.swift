import SwiftUI

struct BottomBar: View {
    let activeHole: Int?
    let holes: [Hole]
    let onTap: () -> Void

    private var activeHoleData: Hole? {
        guard let num = activeHole else { return nil }
        return holes.first(where: { $0.num == num })
    }

    var body: some View {
        if let hole = activeHoleData {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Text("Hole \(hole.num)")
                        .font(.system(size: 15, weight: .semibold))
                    Text("·")
                        .foregroundColor(Color(hex: "#CCCCCC"))
                    Text("Par \(hole.par)")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Color(hex: "#888888"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#FAFAFA"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(hex: "#EEEEEE"), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}
