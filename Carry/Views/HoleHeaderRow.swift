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
                        .foregroundColor(isActive ? Color.textPrimary : Color.textMid)
                    Text("\(hole.par)")
                        .font(.system(size: max(8, numFont * 0.6), weight: .regular))
                        .foregroundColor(isActive ? Color.textSecondary : Color.borderMedium)
                }
                .frame(width: cellWidth, height: rowHeight)
                .id("hole_\(hole.num)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hole \(hole.num), par \(hole.par)\(isActive ? ", active" : "")")
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.gridLine)
                        .frame(width: isNineBoundary ? 2 : 1)
                        .accessibilityHidden(true)
                }
            }

            // Summary columns: Out, In, Tot
            ForEach(["Out", "In", "Tot"], id: \.self) { label in
                Text(label)
                    .font(.system(size: numFont, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                    .frame(width: sumWidth, height: rowHeight)
                    .overlay(alignment: .leading) {
                        if label != "Out" {
                            Rectangle()
                                .fill(Color.gridLine)
                                .frame(width: 1)
                                .accessibilityHidden(true)
                        }
                    }
            }
        }
    }
}
