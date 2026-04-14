import SwiftUI

/// A ViewModifier that wraps a TextField with Carry's standard bordered input styling.
/// Adds dark gray (#333333) border + 1.5pt stroke when focused, light gray border when inactive.
///
/// Usage:
///   TextField("Name", text: $name)
///       .carryInput(focused: isFocused)              // standard (with padding)
///   TextField("HC", text: $hc)
///       .carryInput(focused: isFocused, bare: true)  // no padding (use on pre-padded content)
struct CarryInputModifier: ViewModifier {
    let isFocused: Bool
    var cornerRadius: CGFloat = 14
    var bare: Bool = false

    func body(content: Content) -> some View {
        Group {
            if bare {
                content
            } else {
                content
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
            }
        }
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
    func carryInput(focused: Bool, cornerRadius: CGFloat = 14, bare: Bool = false) -> some View {
        modifier(CarryInputModifier(isFocused: focused, cornerRadius: cornerRadius, bare: bare))
    }
}
