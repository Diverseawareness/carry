import SwiftUI

/// Bottom sheet with a wheel picker for handicap index selection.
/// Supports both regular (0.0–54.0) and plus (+0.1–+10.0) handicaps.
///
/// Usage:
///   .sheet(isPresented: $showPicker) {
///       HandicapPickerSheet(handicap: $handicapValue, isPlus: $isPlusHandicap)
///   }
struct HandicapPickerSheet: View {
    @Binding var handicap: Double
    @Binding var isPlus: Bool
    @Environment(\.dismiss) private var dismiss

    // Local state for picker — committed on Done
    @State private var selectedWhole: Int = 0
    @State private var selectedDecimal: Int = 0
    @State private var localIsPlus: Bool = false

    private let regularWholeRange = Array(0...54)
    private let plusWholeRange = Array(0...10)
    private let decimalRange = Array(0...9)

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Handicap Index")
                .font(.carry.headline)
                .foregroundColor(Color.textPrimary)
                .padding(.top, 24)
                .padding(.bottom, 20)

            // HC / +HC toggle
            HStack(spacing: 0) {
                toggleButton(label: "HC", isSelected: !localIsPlus) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        localIsPlus = false
                        // Clamp value for regular range
                        if selectedWhole > 54 { selectedWhole = 54 }
                    }
                }
                toggleButton(label: "+HC", isSelected: localIsPlus) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        localIsPlus = true
                        // Clamp value for plus range
                        if selectedWhole > 10 { selectedWhole = 10 }
                        if selectedWhole == 10 && selectedDecimal > 0 { selectedDecimal = 0 }
                    }
                }
            }
            .background(Color(hexString: "#F2F2F7"))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 40)
            .padding(.bottom, 16)

            // Wheel picker
            HStack(spacing: 0) {
                // Whole number picker
                Picker("Whole", selection: $selectedWhole) {
                    let range = localIsPlus ? plusWholeRange : regularWholeRange
                    ForEach(range, id: \.self) { num in
                        Text("\(localIsPlus ? "+" : "")\(num)")
                            .tag(num)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 100)
                .clipped()

                Text(".")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(Color.textPrimary)

                // Decimal picker
                Picker("Decimal", selection: $selectedDecimal) {
                    ForEach(decimalRange, id: \.self) { num in
                        Text("\(num)")
                            .tag(num)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 70)
                .clipped()
            }
            .scaleEffect(1.3)
            .frame(height: 260)
            .padding(.horizontal, 20)

            // Clamp +10.0 max
            .onChange(of: selectedWhole) { _, newValue in
                if localIsPlus && newValue >= 10 {
                    selectedWhole = 10
                    selectedDecimal = 0
                }
            }
            .onChange(of: selectedDecimal) { _, _ in
                if localIsPlus && selectedWhole >= 10 {
                    selectedDecimal = 0
                }
            }

            Spacer()

            // Done button
            Button {
                let value = Double(selectedWhole) + Double(selectedDecimal) / 10.0
                handicap = localIsPlus ? -value : value
                isPlus = localIsPlus
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.textPrimary)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .onAppear {
            let absValue = abs(handicap)
            selectedWhole = Int(absValue)
            selectedDecimal = Int((absValue - Double(Int(absValue))) * 10.0 + 0.05) // round safely
            localIsPlus = isPlus || handicap < 0
        }
    }

    private func toggleButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isSelected ? .white : Color.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.textPrimary : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}
