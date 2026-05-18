import SwiftUI

/// Email + password auth sheet — Sign In and Create Account in a single sheet,
/// styled to match `OnboardingView.nameStep` (white background, page title,
/// labeled `carryInput` fields, full-width black CTA).
///
/// `.textContentType(.username)` on the email field plus `.password`
/// (sign-in) / `.newPassword` (sign-up) on the password field is what
/// unlocks iCloud Keychain autofill — without those the fields are
/// anonymous text boxes and iOS won't offer to fill or save credentials.
struct EmailAuthSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    enum Mode { case signIn, signUp }

    @State private var mode: Mode = .signIn
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isLoading = false
    @State private var showCheckEmail = false
    @State private var showForgotPassword = false
    // Resend-email state for the checkEmailView. Cooldown prevents the user
    // from hammering the button into Supabase's send-side rate limit (~3
    // emails/hour on the default sender); 30s window matches what most
    // transactional providers consider polite.
    @State private var resendError: String?
    @State private var isResending = false
    @State private var resendCooldown: Int = 0

    enum Field: Hashable { case firstName, lastName, email, password }
    @FocusState private var focused: Field?

    private let btnRadius: CGFloat = 14

    /// Sign-up password rules. Each line shows below the field while the user
    /// is focused/typing and disappears as it's satisfied. Two rules deliberately
    /// — modern guidance (NIST) discourages heavy complexity, but a digit + length
    /// floor is a sensible minimum.
    private struct PwReq: Identifiable {
        let id: Int
        let text: String
        let isMet: (String) -> Bool
    }

    private let pwRequirements: [PwReq] = [
        .init(id: 0, text: "At least 8 characters", isMet: { $0.count >= 8 }),
        .init(id: 1, text: "Contains a number", isMet: { $0.contains(where: \.isNumber) })
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                if showCheckEmail {
                    checkEmailView
                } else {
                    formView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // "Cancel" while filling the form, "Done" once the
                    // signup has been accepted and the confirmation email
                    // is on its way — same dismiss action, different
                    // contextual label.
                    Button(showCheckEmail ? "Done" : "Cancel") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showForgotPassword) {
                ForgotPasswordView(prefillEmail: email)
            }
        }
        // Override the default system blue tint everywhere within this sheet —
        // toolbar Cancel, keyboard Done, the bottom mode-toggle link, and any
        // other Button label that defaults to .accentColor inherit textPrimary.
        .tint(Color.textPrimary)
        // Attach the toast overlay at the sheet root so toasts fired from
        // anywhere inside this sheet (including pushed destinations like
        // ForgotPasswordView's "Successfully sent" / "Message failed") render
        // within this sheet's window. The MainTabView overlay can't reach
        // into a presented sheet — sheets live in a separate UIWindowScene.
        .carryToastOverlay()
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(mode == .signIn ? "Welcome back" : "Create your account")
                    .font(.carry.pageTitle)
                    .foregroundColor(Color.textPrimary)

                Text(mode == .signIn
                     ? "Sign in to your Carry account."
                     : "Sign up to start tracking skins.")
                    .font(.system(size: 15))
                    .foregroundColor(Color.textTertiary)
                    .padding(.bottom, 8)

                if mode == .signUp {
                    nameFields
                }

                emailField
                passwordField

                if mode == .signIn {
                    forgotLink
                }

                if let error {
                    Text(error)
                        .font(.carry.bodySM)
                        .foregroundColor(Color.systemRedColor)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 4)
                }

                submitButton

                modeToggleLink
                    .padding(.top, 8)

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { focused = nil }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
                    .font(.carry.bodySemibold)
                    .foregroundColor(Color.textPrimary)
            }
        }
    }

    private var nameFields: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("First Name")
                    .font(.carry.bodySMBold)
                    .foregroundColor(Color.textPrimary)
                    .padding(.leading, 4)
                TextField(
                    "",
                    text: $firstName,
                    prompt: Text("First name").foregroundColor(Color.textDisabled)
                )
                    .font(.system(size: 16))
                    .textContentType(.givenName)
                    .submitLabel(.next)
                    .focused($focused, equals: .firstName)
                    .onSubmit { focused = .lastName }
                    .carryInput(focused: focused == .firstName)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Last Name")
                    .font(.carry.bodySMBold)
                    .foregroundColor(Color.textPrimary)
                    .padding(.leading, 4)
                TextField(
                    "",
                    text: $lastName,
                    prompt: Text("Last name").foregroundColor(Color.textDisabled)
                )
                    .font(.system(size: 16))
                    .textContentType(.familyName)
                    .submitLabel(.next)
                    .focused($focused, equals: .lastName)
                    .onSubmit { focused = .email }
                    .carryInput(focused: focused == .lastName)
            }
        }
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Email")
                .font(.carry.bodySMBold)
                .foregroundColor(Color.textPrimary)
                .padding(.leading, 4)
            // `Text(verbatim:)` skips Markdown/data-detector processing —
            // without it iOS sees "you@example.com" as an email pattern and
            // renders the prompt as a tinted link (blue by default).
            // `.foregroundStyle()` is iOS 17's authoritative color override.
            TextField(
                "",
                text: $email,
                prompt: Text(verbatim: "you@example.com")
                    .foregroundStyle(Color.textDisabled)
            )
                .font(.system(size: 16))
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focused, equals: .email)
                .onSubmit { focused = .password }
                .carryInput(focused: focused == .email)
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password")
                .font(.carry.bodySMBold)
                .foregroundColor(Color.textPrimary)
                .padding(.leading, 4)
            SecureField(
                "",
                text: $password,
                prompt: Text("Password").foregroundColor(Color.textDisabled)
            )
                .font(.system(size: 16))
                .textContentType(mode == .signUp ? .newPassword : .password)
                .submitLabel(.go)
                .focused($focused, equals: .password)
                .onSubmit { if canSubmit { submit() } }
                .carryInput(focused: focused == .password)

            passwordRequirementsView
        }
        .animation(.easeOut(duration: 0.2), value: password)
        .animation(.easeOut(duration: 0.2), value: focused)
    }

    /// Live list of unmet password rules — visible only on sign-up while the
    /// field is focused or has any text, and only while at least one rule is
    /// still unsatisfied. Each row removes itself the moment its rule is met.
    @ViewBuilder
    private var passwordRequirementsView: some View {
        let unmet = pwRequirements.filter { !$0.isMet(password) }
        let shouldShow = mode == .signUp
            && (focused == .password || !password.isEmpty)
            && !unmet.isEmpty

        if shouldShow {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(unmet) { req in
                    Text(req.text)
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textTertiary)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.top, 4)
            .padding(.leading, 4)
            .transition(.opacity)
        }
    }

    private var forgotLink: some View {
        Button { showForgotPassword = true } label: {
            Text("Forgot password?")
                .font(.carry.bodySM)
                .foregroundColor(Color.textTertiary)
        }
        .padding(.leading, 4)
        .padding(.top, 2)
    }

    private var submitButton: some View {
        Button { submit() } label: {
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(mode == .signIn ? "Sign In" : "Create Account")
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
        .padding(.top, 16)
    }

    private var modeToggleLink: some View {
        HStack(spacing: 4) {
            Text(mode == .signIn ? "New to Carry?" : "Already have an account?")
                .foregroundColor(Color.textTertiary)
            Button {
                error = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    mode = (mode == .signIn ? .signUp : .signIn)
                }
            } label: {
                Text(mode == .signIn ? "Create an account" : "Sign in")
                    .foregroundColor(Color.textPrimary)
                    .underline()
            }
        }
        .font(.carry.bodySM)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Email confirmation pending state

    /// Continuation state shown after a successful sign-up call that returned
    /// no session (Supabase's "confirm email" path). Lives inside the same
    /// sheet shell as `formView` — same white background, same nav toolbar
    /// (with "Cancel" relabeled to "Done") — so the user experiences it as
    /// the next stage of the sign-up flow, not a separate screen.
    private var checkEmailView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 56))
                    .foregroundColor(Color.textPrimary)

                Text("Check your email")
                    .font(.carry.pageTitle)
                    .foregroundColor(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text("We sent a confirmation link to \(email). Tap it to finish creating your account.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.textTertiary)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)

            Spacer()

            // Resend gives the user a way out when the first email lands in
            // spam or the default sender rate-limited. We re-call signUp with
            // the same credentials; Supabase de-dupes the auth.users row and
            // re-issues the confirmation email.
            VStack(spacing: 12) {
                if let resendError {
                    Text(resendError)
                        .font(.carry.bodySM)
                        .foregroundColor(Color.systemRedColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button { resendConfirmation() } label: {
                    HStack(spacing: 6) {
                        if isResending { ProgressView().tint(Color.textPrimary) }
                        Text(resendCooldown > 0 ? "Resend in \(resendCooldown)s" : "Resend email")
                            .font(.carry.bodySemibold)
                            .foregroundColor(Color.textPrimary)
                    }
                }
                .disabled(isResending || resendCooldown > 0)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty else { return false }
        switch mode {
        case .signIn:
            return !password.isEmpty
        case .signUp:
            let hasFirst = !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            let hasLast = !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            let allReqsMet = pwRequirements.allSatisfy { $0.isMet(password) }
            return hasFirst && hasLast && allReqsMet
        }
    }

    private func submit() {
        focused = nil
        isLoading = true
        error = nil
        Task {
            do {
                let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
                if mode == .signIn {
                    try await authService.signInWithEmail(email: trimmedEmail, password: password)
                    // If we got here from a Google-collision link prompt
                    // (existingProvider="email"), AuthService has stashed
                    // the Google tokens — drain now so Google auto-links to
                    // the just-signed-in account. No-op otherwise.
                    await authService.consumePendingLink()
                    dismiss()
                } else {
                    try await authService.signUpWithEmail(
                        email: trimmedEmail,
                        password: password,
                        firstName: firstName,
                        lastName: lastName
                    )
                    dismiss()
                }
            } catch AuthError.emailConfirmationPending {
                showCheckEmail = true
            } catch let e as AuthError {
                // Typed AuthError (e.g. .emailAlreadyRegistered) carries its own
                // provider-aware copy via errorDescription — use it directly
                // instead of pattern-matching the localizedDescription.
                self.error = e.errorDescription ?? humanError(e)
            } catch {
                self.error = humanError(error)
            }
            isLoading = false
        }
    }

    /// Re-issue the confirmation email by calling signUp again with the same
    /// credentials. Supabase de-dupes the auth.users row (no second user is
    /// created) and re-sends the confirmation email. 30s cooldown afterward
    /// so the button can't be hammered into the sender's rate limit.
    private func resendConfirmation() {
        resendError = nil
        isResending = true
        Task {
            do {
                try await authService.signUpWithEmail(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password,
                    firstName: firstName,
                    lastName: lastName
                )
                // Supabase returned a session on the resend — confirm-email
                // toggle flipped off mid-flight (unlikely) or the user
                // confirmed via another device. Either way we're now signed
                // in; close the sheet so AuthService routing takes over.
                dismiss()
            } catch AuthError.emailConfirmationPending {
                // Expected path — email re-sent, still waiting on the user.
                resendCooldown = 30
                startResendCountdown()
            } catch {
                resendError = "Couldn't resend right now. Wait a minute and try again."
                resendCooldown = 30
                startResendCountdown()
            }
            isResending = false
        }
    }

    private func startResendCountdown() {
        Task {
            while resendCooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if resendCooldown > 0 { resendCooldown -= 1 }
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
        if msg.contains("password") && (msg.contains("6") || msg.contains("8")) {
            return "Password must be at least 8 characters."
        }
        return "Something went wrong. Please try again."
    }
}
