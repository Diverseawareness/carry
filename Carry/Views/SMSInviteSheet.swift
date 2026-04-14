import SwiftUI

/// Shared multi-recipient SMS invite sheet.
/// Used in Quick Game (scorer invites), CreateGroupSheet, ManageMembersSheet, GroupManagerView.
struct SMSInviteSheet: View {
    let title: String
    let message: String
    let onSend: ([String]) -> Void
    let onCancel: () -> Void

    @State private var phoneNumbers: [String] = [""]
    @FocusState private var focusedIndex: Int?

    private var validNumbers: [String] {
        phoneNumbers
            .map { $0.filter { $0.isNumber || $0 == "+" } }
            .filter { $0.count >= 10 }
    }

    private var canSend: Bool { !validNumbers.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            ScrollView {
                scrollContent
            }
            sendButtonSection
        }
        .background(Color.white)
    }

    // MARK: - Sections

    private var headerSection: some View {
        ZStack {
            Text(title)
                .font(.carry.headline)
                .foregroundColor(Color.textPrimary)

            HStack {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.carry.body)
                        .foregroundColor(Color.textTertiary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Phone number fields
            ForEach(Array(phoneNumbers.enumerated()), id: \.offset) { index, _ in
                phoneRow(at: index)
            }

            // Add another button
            Button {
                withAnimation {
                    phoneNumbers.append("")
                    focusedIndex = phoneNumbers.count - 1
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add Another")
                        .font(.carry.bodySMSemibold)
                }
                .foregroundColor(Color.textPrimary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            // Message preview
            VStack(alignment: .leading, spacing: 6) {
                Text("Message Preview")
                    .font(.carry.captionSemibold)
                    .foregroundColor(Color.textDisabled)
                Text(message)
                    .font(.carry.bodySM)
                    .foregroundColor(Color.textTertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSecondary))
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    private func phoneRow(at index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "phone.fill")
                .font(.system(size: 13))
                .foregroundColor(Color.textDisabled)
                .frame(width: 20)

            TextField("Phone number", text: phoneBinding(at: index))
                .font(.carry.body)
                .foregroundColor(Color.textPrimary)
                .keyboardType(.phonePad)
                .focused($focusedIndex, equals: index)

            if phoneNumbers.count > 1 {
                Button {
                    withAnimation {
                        let _ = phoneNumbers.remove(at: index)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.bgSecondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove phone number")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    focusedIndex == index ? Color(hexString: "#333333") : Color.borderLight,
                    lineWidth: focusedIndex == index ? 1.5 : 1
                )
        )
    }

    private var sendButtonSection: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                let numbers = validNumbers
                let recipients = numbers.joined(separator: ",")
                let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "sms:\(recipients)&body=\(encoded)") {
                    UIApplication.shared.open(url)
                }
                onSend(numbers)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .font(.system(size: 14))
                    Text("Send Invite\(validNumbers.count > 1 ? "s" : "")")
                        .font(.carry.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canSend ? Color.textPrimary : Color.borderSubtle)
                )
            }
            .disabled(!canSend)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Color.white)
    }

    private func phoneBinding(at index: Int) -> Binding<String> {
        Binding<String>(
            get: { phoneNumbers[index] },
            set: { newValue in phoneNumbers[index] = newValue }
        )
    }
}
