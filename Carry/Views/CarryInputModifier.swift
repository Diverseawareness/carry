import SwiftUI

/// A ViewModifier that wraps a TextField with Carry's standard bordered input styling.
/// Adds dark gray (#333333) border + 1.5pt stroke when focused, light gray (#D1D1D6) when inactive.
struct CarryInputModifier: ViewModifier {
    let isFocused: Bool
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(.white))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isFocused ? Color(hexString: "#333333") : Color.borderLight,
                        lineWidth: isFocused ? 1.5 : 1
                    )
                    .animation(.easeOut(duration: 0.15), value: isFocused)
            )
    }
}

extension View {
    func carryInput(focused: Bool, cornerRadius: CGFloat = 12) -> some View {
        modifier(CarryInputModifier(isFocused: focused, cornerRadius: cornerRadius))
    }
}
