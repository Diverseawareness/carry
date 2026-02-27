import SwiftUI

struct HoleHeaderRow: View {
    let holes: [Hole]
    let activeHole: Int?
    let cellWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 52)
            ForEach(holes) { hole in
                VStack(spacing: 1) {
                    Text("\(hole.num)")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundColor(hole.num == activeHole ? Color(hex: "1A1A1A") : Color(hex: "D8D8D8"))
                    Text("\(hole.par)")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "EBEBEB"))
                }
                .frame(width: cellWidth, height: 32)
            }
        }
    }
}
