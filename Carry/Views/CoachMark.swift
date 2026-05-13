import SwiftUI

/// Reusable dark-callout coach mark with a triangle pointer.
///
/// Matches the Figma design (1480:3083) — `Color.textPrimary` (~#1c1c1c)
/// fill, white semibold body, 16pt padding, 10pt rounded corners, ~175pt
/// fixed text width, top-anchored upward-pointing triangle.
///
/// Default usage: tap anywhere to dismiss. Caller wires `onDismiss` to
/// flip a UserDefaults flag so the same callout doesn't re-render.
struct CoachMark: View {
    let text: String
    /// Horizontal offset of the triangle pointer from the leading edge of
    /// the bubble. Use this so the pointer aligns with whatever the coach
    /// mark is calling out (e.g., position it under a button on the right
    /// side of a header).
    var pointerLeadingOffset: CGFloat = 12
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pointer triangle — points UP at the anchored UI element above.
            Triangle()
                .fill(Color.textPrimary)
                .frame(width: 16, height: 11)
                .padding(.leading, pointerLeadingOffset)

            // Bubble
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineSpacing(4)
                .frame(width: 176, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.textPrimary)
                )
        }
        .onTapGesture { onDismiss() }
        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
    }
}

/// Upward-pointing triangle for the CoachMark pointer.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
