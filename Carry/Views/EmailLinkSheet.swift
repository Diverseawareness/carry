import SwiftUI

/// Sheet for adding an email/password identity to an already-signed-in user.
///
/// Reached from the SIGN-IN METHODS section in ProfileSheetView when the user
/// taps the **Email** "Connect" row. Captures a single password (the email
/// address is implicit — it's already on the auth row from the original
/// Apple/Google sign-in) and calls `AuthService.linkEmailIdentity(password:)`.
///
/// Password requirements mirror `EmailAuthSheet`'s signup form (8+ chars +
/// digit) so users who sign in via email later get a consistent floor.
struct EmailLinkSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var password: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    @FocusState private var focused: Bool

    private struct PwReq: Identifiable {
        let id: Int
        let text: String
        let isMet: (String) -> Bool
    }

    private let pwRequirements: [PwReq] = [
        .init(id: 0, text: "At least 8 characters", isMet: { $0.count >= 8 }),
        .init(id: 1, text: "Contains a number", isMet: { $0.contains(where: \.isNumber) })
    ]

    private var canSubmit: Bool {
        pwRequirements.allSatisfy { $0.isMet(password) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Add email & password")
                            .font(.carry.pageTitle)
                            .foregroundColor(Color.textPrimary)

                        Text("Set a password so you can sign in with \(authService.currentUser?.email ?? "your email") and password in addition to your current method.")
                            .font(.system(size: 15))
                            .foregroundColor(Color.textTertiary)
                            .padding(.bottom, 8)

                        Text("Password")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                            .padding(.leading, 4)

                        SecureField(
                            "",
                            text: $password,
                            prompt: Text(verbatim: "Choose a password")
                                .foregroundStyle(Color.textDisabled)
                        )
                            .font(.system(size: 16))
                            .foregroundColor(Color.textPrimary)
                            .textContentType(.newPassword)
                            .submitLabel(.go)
                            .focused($focused)
                            .onSubmit { if canSubmit { submit() } }
                            .carryInput(focused: focused)

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(pwRequirements) { req in
                                HStack(spacing: 6) {
                                    Image(systemName: req.isMet(password) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(req.isMet(password) ? Color.successGreen : Color.textTertiary)
                                        .font(.system(size: 13))
                                    Text(req.text)
                                        .font(.system(size: 13))
                                        .foregroundColor(req.isMet(password) ? Color.successGreen : Color.textTertiary)
                                }
                            }
                        }
                        .padding(.top, 4)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.carry.bodySM)
                                .foregroundColor(Color.systemRedColor)
                                .padding(.top, 4)
                        }

                        Button { submit() } label: {
                            ZStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Save")
                                        .font(.carry.headlineBold)
                                        .foregroundColor(canSubmit ? .white : Color.textDisabled)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(canSubmit ? Color.textPrimary : Color.borderSubtle)
                            )
                        }
                        .disabled(!canSubmit || isLoading)
                        .padding(.top, 16)

                        Spacer().frame(height: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                        .font(.carry.bodySemibold)
                        .foregroundColor(Color.textPrimary)
                }
            }
            .onAppear { focused = true }
        }
        .tint(Color.textPrimary)
        .carryToastOverlay()
    }

    private func submit() {
        focused = false
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.linkEmailIdentity(password: password)
                ToastManager.shared.success("Email connected")
                dismiss()
            } catch AuthService.LinkError.alreadyLinked {
                errorMessage = "Email is already connected to your account."
            } catch let e as AuthService.LinkError {
                errorMessage = e.errorDescription ?? "Couldn't connect email. Please try again."
            } catch {
                errorMessage = "Couldn't connect email. Please try again."
            }
            isLoading = false
        }
    }
}
