import SwiftUI

/// Reusable dark-callout coach mark with a triangle pointer.
///
/// Matches the Figma design (1480:3083) — `Color.textPrimary` (~#1c1c1c)
/// fill, white semibold body, 16pt padding, 10pt rounded corners, ~175pt
/// fixed text width, top-anchored upward-pointing triangle.
///
/// The pointer can be aligned to either the leading or trailing edge of
/// the bubble via `pointerSide`. Use `.trailing` when the affordance is
/// near the right side of the screen so the bubble extends LEFT (avoids
/// clipping past the right edge).
///
/// Default usage: tap anywhere to dismiss. Caller wires `onDismiss` to
/// flip a UserDefaults flag so the same callout doesn't re-render.
struct CoachMark: View {
    let text: String
    /// Which side of the bubble the pointer sits on. Bubble extends in the
    /// opposite direction (e.g., `.trailing` pointer = bubble extends left).
    var pointerSide: PointerSide = .leading
    /// Inset of the pointer from its anchored side (in pt). For `.leading`,
    /// distance from bubble's left edge to pointer's left edge. For
    /// `.trailing`, distance from bubble's right edge to pointer's right edge.
    var pointerInset: CGFloat = 12
    var onDismiss: () -> Void

    enum PointerSide {
        case leading, trailing
    }

    private let bubbleWidth: CGFloat = 176
    private let pointerWidth: CGFloat = 16
    private let pointerHeight: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pointer triangle — points UP at the anchored UI element above.
            // Position it via leading padding computed from pointerSide+inset.
            Triangle()
                .fill(Color.textPrimary)
                .frame(width: pointerWidth, height: pointerHeight)
                .padding(.leading, pointerLeadingPadding)

            // Bubble — fixed-width text + dark fill
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineSpacing(4)
                .frame(width: bubbleWidth, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.textPrimary)
                )
        }
        .onTapGesture { onDismiss() }
        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
    }

    /// Distance from bubble's leading edge to triangle's leading edge.
    /// Computed so trailing-anchored pointers sit `pointerInset` from the
    /// right side of the bubble (accounting for padding + bubble width).
    private var pointerLeadingPadding: CGFloat {
        switch pointerSide {
        case .leading:
            return pointerInset
        case .trailing:
            // Total bubble outer width = bubbleWidth + 32 (padding both sides).
            // Triangle's leading position = (total bubble width) - pointerInset - pointerWidth
            return (bubbleWidth + 32) - pointerInset - pointerWidth
        }
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
