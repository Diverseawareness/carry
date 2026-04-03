import SwiftUI

/// Shared tee-time / schedule picker used by both the Create Group sheet
/// and the Game Options sheet.
struct TeeTimePickerSheet: View {
    // 0 = Single Game, 1 = Recurring
    @Binding var scheduleMode: Int
    @Binding var selectedDate: Date
    // 0 = Weekly, 1 = Biweekly, 2 = Monthly
    @Binding var repeatMode: Int
    // 0 = Mon … 6 = Sun (nil = none selected)
    @Binding var selectedDayPill: Int?

    var onSet: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Tab toggle: Single Game / Recurring
                    HStack(spacing: 0) {
                        ForEach(Array(["Single Game", "Recurring"].enumerated()), id: \.offset) { idx, label in
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    scheduleMode = idx
                                    if idx == 0 {
                                        // Switching to Single – clear day pill selection
                                        selectedDayPill = nil
                                    } else if repeatMode == 0 {
                                        // Switching to Recurring – default Weekly
                                        if selectedDayPill == nil {
                                            let weekday = Calendar.current.component(.weekday, from: selectedDate)
                                            selectedDayPill = GameRecurrence.pillIndex(fromWeekday: weekday)
                                        }
                                    }
                                }
                            } label: {
                                Text(label)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(scheduleMode == idx ? .white : Color.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        Capsule().fill(scheduleMode == idx ? Color.textPrimary : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Capsule().fill(Color.bgPrimary))
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 8)

                    // Date & time label
                    Text(scheduleMode == 0 ? "Date & Time" : "Start Date & Time")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                        .padding(.top, 20)

                    DatePicker(
                        "",
                        selection: $selectedDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 120)
                    .clipped()
                    .padding(.horizontal, 40)
                    .padding(.top, 8)

                    // Recurring-only: Frequency + Day picker
                    if scheduleMode == 1 {
                        VStack(spacing: 16) {
                            Text("How Often?")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color.textPrimary)

                            HStack(spacing: 8) {
                                ForEach(Array(["Weekly", "Biweekly", "Monthly"].enumerated()), id: \.offset) { idx, label in
                                    Button {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            repeatMode = idx
                                            if idx <= 1 && selectedDayPill == nil {
                                                let weekday = Calendar.current.component(.weekday, from: selectedDate)
                                                selectedDayPill = GameRecurrence.pillIndex(fromWeekday: weekday)
                                            }
                                            if idx == 2 { selectedDayPill = nil }
                                        }
                                    } label: {
                                        Text(label)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(repeatMode == idx ? .white : Color.textPrimary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(
                                                Capsule().fill(repeatMode == idx ? Color.textPrimary : Color.bgPrimary)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Day-of-week pills (visible for Weekly / Biweekly)
                            if repeatMode == 0 || repeatMode == 1 {
                                let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
                                HStack(spacing: 6) {
                                    ForEach(0..<7, id: \.self) { i in
                                        Button {
                                            withAnimation(.easeOut(duration: 0.15)) {
                                                selectedDayPill = i
                                            }
                                        } label: {
                                            Text(dayLabels[i])
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(selectedDayPill == i ? .white : Color.textPrimary)
                                                .frame(width: 40, height: 40)
                                                .background(
                                                    Circle().fill(selectedDayPill == i ? Color.textPrimary : Color.bgPrimary)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.top, 24)
                    }

                    Spacer().frame(height: 24)
                }
            }

            Spacer()

            // Set button — pinned at bottom
            Button {
                onSet()
            } label: {
                Text(scheduleMode == 1 ? "Set Schedule" : "Set Tee Time")
                    .font(.carry.bodyLGSemibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.textPrimary)
                    )
            }
            .padding(.horizontal, 24)

            // Cancel button
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.carry.bodySM)
                    .foregroundColor(Color.dividerMuted)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
    }
}
