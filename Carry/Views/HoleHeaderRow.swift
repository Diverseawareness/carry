import SwiftUI

struct HoleHeaderRow: View {
    let holes: [Hole]
    let activeHole: Int?
    let cellWidth: CGFloat
    let sumWidth: CGFloat
    let rowHeight: CGFloat
    let numFont: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(holes) { hole in
                let isActive = hole.num == activeHole
                let isNineBoundary = hole.num == 9

                VStack(spacing: -2) {
                    Text("\(hole.num)")
                        .font(.system(size: numFont, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(isActive ? Color(hex: "#1A1A1A") : Color(hex: "#888888"))
                    Text("\(hole.par)")
                        .font(.system(size: max(8, numFont * 0.6), weight: .regular))
                        .foregroundColor(isActive ? Color(hex: "#999999") : Color(hex: "#CCCCCC"))
                }
                .frame(width: cellWidth, height: rowHeight)
                .id("hole_\(hole.num)")
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(isNineBoundary ? Color(hex: "#E0E0E0") : Color(hex: "#F0F0F0"))
                        .frame(width: isNineBoundary ? 2 : 1)
                }
            }

            // Summary columns: Out, In, Tot
            ForEach(["Out", "In", "Tot"], id: \.self) { label in
                Text(label)
                    .font(.system(size: numFont, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                    .frame(width: sumWidth, height: rowHeight)
                    .overlay(alignment: .leading) {
                        if label == "Out" {
                            Rectangle()
                                .fill(Color(hex: "#E0E0E0"))
                                .frame(width: 2)
                        }
                    }
            }
        }
    }
}
