import SwiftUI

/// In-app password reset sheet. Presented when the user taps a recovery
/// email link, `CarryApp.handleIncomingURL` routes the Universal Link to
/// `AuthService.beginPasswordRecovery`, the PKCE code is exchanged for a
/// temporary recovery session, and `isInPasswordRecovery` flips true.
///
/// After Save: `completePasswordRecovery` updates the password and signs
/// the user out, so they re-enter via the welcome screen with the new
/// password — no half-state where the next API call would still use the
/// recovery JWT.
struct PasswordRecoverySheet: View {
    @EnvironmentObject var authService: AuthService

    @State private var password: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false

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
                        Text("Set a new password")
                            .font(.carry.pageTitle)
                            .foregroundColor(Color.textPrimary)

                        Text("Enter a new password for your Carry account. You'll be signed back in with it.")
                            .font(.system(size: 15))
                            .foregroundColor(Color.textTertiary)
                            .padding(.bottom, 8)

                        // Hidden username field — iOS needs a focusable
                        // TextField with .textContentType(.username) paired
                        // with the .newPassword field below for iCloud
                        // Keychain to offer to save the new credentials.
                        TextField("", text: .constant(authService.recoveryEmail ?? ""))
                            .textContentType(.username)
                            .frame(height: 0)
                            .opacity(0)
                            .disabled(true)
                            .accessibilityHidden(true)

                        Text("New password")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                            .padding(.leading, 4)

                        Group {
                            if showPassword {
                                TextField(
                                    "",
                                    text: $password,
                                    prompt: Text(verbatim: "Choose a password")
                                        .foregroundStyle(Color.textDisabled)
                                )
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                            } else {
                                SecureField(
                                    "",
                                    text: $password,
                                    prompt: Text(verbatim: "Choose a password")
                                        .foregroundStyle(Color.textDisabled)
                                )
                            }
                        }
                            .font(.system(size: 16))
                            .foregroundColor(Color.textPrimary)
                            .textContentType(.newPassword)
                            .submitLabel(.go)
                            .focused($focused)
                            .onSubmit { if canSubmit { submit() } }
                            .carryInput(focused: focused)
                            .overlay(alignment: .trailing) {
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.textSecondary)
                                        .padding(.trailing, 14)
                                        .frame(maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                            }

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
                                    Text("Save password")
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
                    Button("Cancel") {
                        Task { await authService.cancelPasswordRecovery() }
                    }
                }
            }
            .onAppear { focused = true }
            .interactiveDismissDisabled(true)
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
                try await authService.completePasswordRecovery(newPassword: password)
                ToastManager.shared.success("Password updated. Sign in with your new password.")
            } catch {
                errorMessage = "Couldn't update password. Try requesting a new reset link."
                isLoading = false
            }
        }
    }
}
