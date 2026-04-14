import SwiftUI

/// Self-contained text field with Carry's bordered input styling.
/// Automatically tracks focus and applies dark stroke when active.
///
/// Usage:
///   CarryTextField("Enter name", text: $name)
///   CarryTextField("HC", text: $hc, keyboardType: .decimalPad, alignment: .center, width: 56)
struct CarryTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var alignment: TextAlignment = .leading
    var width: CGFloat? = nil
    var height: CGFloat = 50
    var disabled: Bool = false
    var leadingContent: AnyView? = nil
    var trailingContent: AnyView? = nil

    /// Optional filter applied on every keystroke (e.g. `filterHandicapInput`).
    var inputFilter: ((String) -> String)? = nil

    /// Called when focus changes. Use to track which field is active at the parent level.
    var onFocusChange: ((Bool) -> Void)? = nil

    init(_ placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default, alignment: TextAlignment = .leading, width: CGFloat? = nil, height: CGFloat = 50, disabled: Bool = false, leadingContent: AnyView? = nil, trailingContent: AnyView? = nil, inputFilter: ((String) -> String)? = nil, onFocusChange: ((Bool) -> Void)? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
        self.alignment = alignment
        self.width = width
        self.height = height
        self.disabled = disabled
        self.leadingContent = leadingContent
        self.trailingContent = trailingContent
        self.inputFilter = inputFilter
        self.onFocusChange = onFocusChange
    }

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let leading = leadingContent {
                leading
            }

            TextField(placeholder, text: $text)
                .font(.carry.bodyLG)
                .foregroundColor(Color.textPrimary)
                .keyboardType(keyboardType)
                .multilineTextAlignment(alignment)
                .focused($isFocused)
                .disabled(disabled)
                .onChange(of: text) { _, newValue in
                    guard let filter = inputFilter else { return }
                    let filtered = filter(newValue)
                    if filtered != newValue {
                        text = newValue
                        DispatchQueue.main.async {
                            text = filtered
                        }
                    }
                }
                .onChange(of: isFocused) { _, newValue in
                    onFocusChange?(newValue)
                }

            if let trailing = trailingContent {
                trailing
            }
        }
        .padding(.horizontal, width != nil ? 6 : (leadingContent != nil || trailingContent != nil ? 12 : 21))
        .frame(height: height)
        .frame(width: width)
        .contentShape(Rectangle())
        .carryInput(focused: isFocused, bare: true)
    }
}
