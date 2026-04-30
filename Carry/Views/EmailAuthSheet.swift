import SwiftUI

struct EmailAuthSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Sign Up"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isLoading = false
    @State private var showCheckEmail = false
    @State private var showResetSent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if showCheckEmail {
                        checkEmailView
                    } else {
                        formView
                    }
                }
                .padding(24)
            }
            .navigationTitle("Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Reset link sent", isPresented: $showResetSent) {
                Button("OK") {}
            } message: {
                Text("Check your email for a password reset link.")
            }
        }
    }

    private var formView: some View {
        VStack(spacing: 20) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 12) {
                Text("Email")
                    .font(.carry.captionLG)
                    .foregroundColor(.secondary)
                TextField("you@example.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))

                Text("Password")
                    .font(.carry.captionLG)
                    .foregroundColor(.secondary)
                SecureField("••••••••", text: $password)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))

                if mode == .signIn {
                    Button("Forgot password?") { resetPassword() }
                        .font(.carry.captionLG)
                        .foregroundColor(Color.textMid)
                }

                if mode == .signUp {
                    Text("We'll send a confirmation email — tap the link to finish creating your account.")
                        .font(.carry.captionLG)
                        .foregroundColor(.secondary)
                }
            }

            if let error {
                Text(error)
                    .font(.carry.captionLG)
                    .foregroundColor(Color.systemRedColor)
                    .multilineTextAlignment(.center)
            }

            Button(action: submit) {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(mode == .signIn ? "Sign In" : "Create Account")
                            .font(.carry.label)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 18).fill(.black))
            }
            .disabled(isLoading || !canSubmit)
        }
    }

    private var checkEmailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 56))
                .foregroundColor(Color(hexString: "#064102"))

            Text("Check your email")
                .font(.system(size: 24, weight: .bold))

            Text("We sent a confirmation link to \(email). Tap it to finish creating your account, then come back and sign in.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("Done") { dismiss() }
                .font(.carry.label)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 18).fill(.black))
                .padding(.top, 16)
        }
        .padding(.top, 40)
    }

    private var canSubmit: Bool {
        !email.isEmpty && password.count >= 6
    }

    private func submit() {
        isLoading = true
        error = nil
        Task {
            do {
                if mode == .signIn {
                    try await authService.signInWithEmail(email: email, password: password)
                    dismiss()
                } else {
                    try await authService.signUpWithEmail(email: email, password: password)
                    dismiss()
                }
            } catch AuthError.emailConfirmationPending {
                showCheckEmail = true
            } catch {
                self.error = humanError(error)
            }
            isLoading = false
        }
    }

    private func resetPassword() {
        guard !email.isEmpty else {
            error = "Enter your email first."
            return
        }
        Task {
            do {
                try await authService.sendPasswordReset(email: email)
                showResetSent = true
            } catch {
                self.error = "Couldn't send reset email. Try again."
            }
        }
    }

    private func humanError(_ e: Error) -> String {
        let msg = e.localizedDescription.lowercased()
        if msg.contains("invalid login") || msg.contains("invalid_credentials") {
            return "Email or password is wrong."
        }
        if msg.contains("already registered") || msg.contains("user_already_exists") {
            return "An account with this email already exists. Try signing in instead."
        }
        if msg.contains("password") && msg.contains("6") {
            return "Password must be at least 6 characters."
        }
        return "Something went wrong. Please try again."
    }
}
