import SwiftUI

/// Push destination from `EmailAuthSheet`'s sign-in mode. Layout follows
/// Figma node 1370:3502 (pill "Back" button top-left, "Send Instructions"
/// CTA), but type ramp + control sizes use Carry's tokens — `.carry.pageTitle`
/// for the heading, `.carry.headlineBold` on the CTA, 56pt button height with
/// the standard 14pt radius, and the shared `.carryInput()` modifier on the
/// email field — to stay consistent with `OnboardingView.nameStep`.
struct ForgotPasswordView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    /// Email value pulled from the sign-in form so the user doesn't retype.
    var prefillEmail: String = ""

    @State private var email: String = ""
    @State private var isLoading = false

    enum Field: Hashable { case email }
    @FocusState private var focused: Field?

    private let btnRadius: CGFloat = 14

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            formView
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
                    .font(.carry.bodySemibold)
                    .foregroundColor(Color.textPrimary)
            }
        }
        .onAppear {
            if email.isEmpty { email = prefillEmail }
        }
    }

    // MARK: - Back button (text pill, top-left)

    private var backButton: some View {
        Button { dismiss() } label: {
            Text("Back")
                .font(.system(size: 18))
                .foregroundColor(Color.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                )
        }
    }

    // MARK: - Form

    private var formView: some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton
                .padding(.leading, 24)
                .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 36)

                    Text("Forgot password?")
                        .font(.carry.pageTitle)
                        .foregroundColor(Color.textPrimary)

                    Text("No worries, we'll send you reset instructions")
                        .font(.system(size: 15))
                        .foregroundColor(Color.textTertiary)
                        .padding(.top, 4)

                    Spacer().frame(height: 32)

                    Text("Email")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    TextField(
                        "",
                        text: $email,
                        prompt: Text(verbatim: "Enter email")
                            .foregroundStyle(Color.textDisabled)
                    )
                        .font(.system(size: 16))
                        .foregroundColor(Color.textPrimary)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focused, equals: .email)
                        .onSubmit { if canSubmit { submit() } }
                        .carryInput(focused: focused == .email)
                        .padding(.top, 6)

                    Spacer().frame(height: 24)

                    Button { submit() } label: {
                        ZStack {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Send Instructions")
                                    .font(.carry.headlineBold)
                                    .foregroundColor(canSubmit ? .white : Color.textDisabled)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: btnRadius)
                                .fill(canSubmit ? Color.textPrimary : Color.borderSubtle)
                        )
                    }
                    .disabled(!canSubmit || isLoading)

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onTapGesture { focused = nil }
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        // Basic shape: `local@domain.tld`. Catches the common typos
        // (`dani`, `dani@`, `dani@gmail`) before we waste a reset email
        // round-trip. Full RFC validation lives on Supabase; this is UX gating.
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.range(
            of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#,
            options: .regularExpression
        ) != nil
    }

    private func submit() {
        focused = nil
        isLoading = true
        Task {
            do {
                let trimmed = email.trimmingCharacters(in: .whitespaces)
                try await authService.sendPasswordReset(email: trimmed)
                // Clear field on success so an accidental second tap doesn't
                // resend; user reads the toast for confirmation.
                email = ""
                ToastManager.shared.success("Successfully sent, check your email")
            } catch {
                // Keep field populated so the user can tweak and retry without
                // retyping the address.
                ToastManager.shared.error("Message failed, check email and try again")
            }
            isLoading = false
        }
    }
}
