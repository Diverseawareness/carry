import Foundation
import UIKit
import AuthenticationServices
import Supabase
import PostHog

@MainActor
final class AuthService: ObservableObject {
    @Published var currentUser: ProfileDTO?
    @Published var isAuthenticated = false
    @Published var isOnboarded = false
    @Published var isLoading = true
    @Published var isNewUser = false  // true after first sign-in, triggers profile sheet
    @Published var identities: [UserIdentity] = []  // sign-in methods linked to current user

    /// Set when a Google (or future provider) sign-in attempt is blocked by the
    /// server-side dedupe trigger because the email already has a different
    /// provider account. The Google tokens are stashed here so the UI can
    /// route the user through the existing-provider sign-in (Apple / email)
    /// and then auto-link Google to the now-authenticated user.
    ///
    /// Cleared after `consumePendingLink()` runs or after the user cancels
    /// the confirmation prompt. Memory-only (process-local) — not persisted,
    /// since a fresh app launch invalidates any stashed Google ID token
    /// (~1hr expiry) anyway.
    @Published var pendingProviderLink: PendingProviderLink?

    private let client = SupabaseManager.shared.client

    /// Int player ID derived from the profile UUID, matching Player.init(from:) conversion.
    /// Falls back to 1 in dev mode when no profile is loaded.
    var currentPlayerId: Int {
        if let profile = currentUser {
            #if DEBUG
            // In dev mode with the seeded demo profile, return 1
            // to match demo data creatorId values.
            if !isAuthenticated {
                return 1
            }
            #endif
            return Player.stableId(from: profile.id)
        }
        return 1
    }

    init() {
        #if DEBUG
        // Seed a demo profile so Profile tab has data in dev mode.
        // checkSession() will overwrite if a real session exists.
        currentUser = ProfileDTO(
            id: UUID(),
            firstName: "Daniel",
            lastName: "Sigvardsson",
            username: nil,
            displayName: "Daniel S",
            initials: "DS",
            color: "#BCF0B5",
            avatar: "🏌️",
            handicap: 6.5,
            ghinNumber: "1234567",
            homeClub: "Ruby Hill GC, Pleasanton, CA",
            homeClubId: 12345,
            email: "daniel@example.com",
            createdAt: nil,
            updatedAt: nil
        )
        #endif
        Task { await checkSession() }
    }

    // MARK: - Session

    /// Onboarding is complete only if the user finished it in this install.
    private var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: "onboardingCompleted")
    }

    /// A profile is valid for skipping onboarding if the user has previously
    /// completed the Golf Profile step (homeClub is required there). A real
    /// displayName alone isn't proof — Apple Sign In writes the Apple name to
    /// the profile before onboarding runs, so a brand-new Apple user has a real
    /// displayName but no homeClub.
    private var hasValidProfile: Bool {
        guard let profile = currentUser else { return false }
        let name = profile.displayName.trimmingCharacters(in: .whitespaces)
        let hasRealName = !name.isEmpty && name != "Player"
        let hasHomeClub = profile.homeClubId != nil ||
            (profile.homeClub.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false)
        if hasRealName && hasHomeClub {
            if !hasCompletedOnboarding {
                UserDefaults.standard.set(true, forKey: "onboardingCompleted")
            }
            return true
        }
        return false
    }

    func checkSession() async {
        defer { isLoading = false }
        do {
            let session = try await client.auth.session
            await loadProfile(userId: session.user.id)
            await refreshIdentities()
            isAuthenticated = true
            isOnboarded = hasValidProfile
            // Identify user in PostHog
            if let profile = currentUser {
                PostHogSDK.shared.identify(session.user.id.uuidString, userProperties: [
                    "name": profile.displayName,
                    "handicap": profile.handicap
                ])
            }
            // Register for push notifications on session restore (only if already onboarded —
            // new users get the prompt during onboarding's "Enable Notifications" step).
            //
            // We deliberately DO NOT also check the local `disclaimerAccepted` UserDefaults
            // flag here. UserDefaults gets wiped on app delete, but Apple preserves the
            // Supabase Keychain session across delete+reinstall — meaning a returning user
            // who reinstalls hits this session-restore path with `isOnboarded=true` (from
            // the server) but `disclaimerAccepted=false` (UserDefaults reset). With the
            // old `&& disclaimerAccepted` gate, permission was never requested, the
            // Notifications row never appeared in iOS Settings, and pushes silently
            // failed forever for that user. The server-side `isOnboarded=true` is
            // sufficient evidence that the user has completed the disclaimer at some
            // point in their account's history.
            //
            // Sync the local disclaimerAccepted flag to match the server truth so any
            // other code paths that check it locally see a consistent value after this
            // restore.
            if isOnboarded {
                if !UserDefaults.standard.bool(forKey: "disclaimerAccepted") {
                    UserDefaults.standard.set(true, forKey: "disclaimerAccepted")
                }
                NotificationService.shared.requestPermissionAndRegister()
            }
        } catch {
            isAuthenticated = false
            #if !DEBUG
            currentUser = nil
            #endif
        }
    }

    // MARK: - Provider-agnostic post-auth wrap-up
    //
    // Apple/Google/Email all share the same end-of-flow steps: load profile,
    // flip auth flags, identify in PostHog, and decide if the user needs to
    // run onboarding. The only thing that differs is how we got the session.
    private func finishProviderSignIn(userId: UUID, providerLabel: String) async {
        await loadProfile(userId: userId)
        await refreshIdentities()
        isAuthenticated = true

        if let profile = currentUser {
            PostHogSDK.shared.identify(userId.uuidString, userProperties: [
                "name": profile.displayName,
                "handicap": profile.handicap
            ])
            isNewUser = !hasValidProfile
        } else {
            isNewUser = true
        }
        PostHogSDK.shared.capture("user_signed_in", properties: ["provider": providerLabel])

        isOnboarded = isNewUser ? false : hasValidProfile

        if isOnboarded {
            NotificationService.shared.requestPermissionAndRegister()
        }
    }

    // MARK: - Apple Sign-In

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.missingToken
        }

        let session = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: tokenString
            )
        )

        // Build profile update from Apple-provided data
        var update = ProfileUpdate()

        // Name from Apple (only sent on first sign-in)
        if let fullName = credential.fullName {
            let first = fullName.givenName ?? ""
            let last = fullName.familyName ?? ""
            let display = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            if !display.isEmpty {
                update.firstName = first
                update.lastName = last
                update.displayName = display
                update.initials = String(display.prefix(2)).uppercased()
            }
        }

        // Email from Apple credential or Supabase session
        let email = credential.email ?? session.user.email
        if let email, !email.isEmpty {
            update.email = email
        }

        // Apply update if we have anything
        if update.displayName != nil || update.email != nil {
            _ = try? await client.from("profiles")
                .update(update)
                .eq("id", value: session.user.id.uuidString)
                .execute()
        }

        await finishProviderSignIn(userId: session.user.id, providerLabel: "apple")
    }

    // MARK: - Google Sign-In
    //
    // Caller (AuthView) drives the GIDSignIn flow and hands us the idToken.
    // We just exchange it with Supabase, exactly like the Apple path.
    func signInWithGoogle(idToken: String, accessToken: String?, nonce: String) async throws {
        let session: Session
        do {
            session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: accessToken,
                    nonce: nonce
                )
            )
        } catch {
            // Server-side dedup trigger (migration 20260515000000) may raise
            // EMAIL_ALREADY_REGISTERED: <provider> if a user with this email
            // already exists under a different sign-in method. Translate
            // to typed AuthError so the UI can show "use Apple instead", etc.
            throw mapAuthSignupError(error)
        }

        // Backfill profile from Google claims. Supabase normalizes the idToken
        // into userMetadata as `name`/`full_name` (not `given_name`/`family_name`),
        // so we split `name` on first space.
        let metadata = session.user.userMetadata
        var first = ""
        var last = ""
        if let fullName = metadata["name"]?.stringValue, !fullName.isEmpty {
            let parts = fullName.split(separator: " ", maxSplits: 1).map(String.init)
            first = parts.first ?? fullName
            last = parts.count > 1 ? parts[1] : ""
        }
        let avatar = metadata["picture"]?.stringValue ?? metadata["avatar_url"]?.stringValue ?? ""
        let email = session.user.email ?? metadata["email"]?.stringValue

        var update = ProfileUpdate()
        let display = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !display.isEmpty {
            update.firstName = first
            update.lastName = last
            update.displayName = display
            update.initials = String(display.prefix(2)).uppercased()
        }
        if let email, !email.isEmpty { update.email = email }
        if !avatar.isEmpty { update.avatarUrl = avatar }

        if update.displayName != nil || update.email != nil || update.avatarUrl != nil {
            _ = try? await client.from("profiles")
                .update(update)
                .eq("id", value: session.user.id.uuidString)
                .execute()
        }

        await finishProviderSignIn(userId: session.user.id, providerLabel: "google")
    }

    // MARK: - Identity Linking
    //
    // Lets a signed-in user attach an additional sign-in method to the SAME
    // account, so signing in via Apple or Google later lands on the same
    // profile/data instead of creating a duplicate user.
    //
    // Backed by Supabase's `linkIdentityWithIdToken`, which takes the same
    // OIDC credentials as `signInWithIdToken` but with the link flag set.

    enum LinkError: LocalizedError {
        case alreadyLinked
        case alreadyLinkedToOtherUser
        case lastIdentity
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .alreadyLinked: return "This sign-in method is already connected."
            case .alreadyLinkedToOtherUser: return "This account is already linked to a different Carry user. Sign in with that account instead."
            case .lastIdentity: return "You can't disconnect your only sign-in method."
            case .underlying(let error): return error.localizedDescription
            }
        }
    }

    func refreshIdentities() async {
        do {
            identities = try await client.auth.userIdentities()
        } catch {
            #if DEBUG
            print("[AuthService] refreshIdentities failed: \(error)")
            #endif
        }
    }

    func linkAppleIdentity(idTokenString: String, nonce: String? = nil) async throws {
        if identities.contains(where: { $0.provider == "apple" }) {
            throw LinkError.alreadyLinked
        }
        do {
            _ = try await client.auth.linkIdentityWithIdToken(
                credentials: .init(provider: .apple, idToken: idTokenString, nonce: nonce)
            )
            await refreshIdentities()
        } catch {
            throw mapLinkError(error)
        }
    }

    func linkGoogleIdentity(idToken: String, accessToken: String?, nonce: String) async throws {
        if identities.contains(where: { $0.provider == "google" }) {
            throw LinkError.alreadyLinked
        }
        do {
            _ = try await client.auth.linkIdentityWithIdToken(
                credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken, nonce: nonce)
            )
            await refreshIdentities()
        } catch {
            throw mapLinkError(error)
        }
    }

    /// Add an email/password identity to the already-signed-in user. Unlike
    /// the OAuth link paths, there's no token exchange — the user is already
    /// authenticated via Apple/Google with a verified email on their auth
    /// row, so all we need is to SET a password. Once set, they can sign in
    /// via the Email tab using that email + password, landing on the same
    /// profile.
    ///
    /// Implementation: `client.auth.update(user: UserAttributes(password:))`
    /// updates the current session's user. Supabase adds an `email` provider
    /// row to `auth.identities` so `refreshIdentities()` picks it up and the
    /// SIGN-IN METHODS row flips to "Connected ✓".
    func linkEmailIdentity(password: String) async throws {
        if identities.contains(where: { $0.provider == "email" }) {
            throw LinkError.alreadyLinked
        }
        do {
            _ = try await client.auth.update(user: UserAttributes(password: password))
            await refreshIdentities()
        } catch {
            throw mapLinkError(error)
        }
    }

    func unlinkProvider(_ provider: String) async throws {
        guard identities.count > 1 else {
            throw LinkError.lastIdentity
        }
        guard let identity = identities.first(where: { $0.provider == provider }) else {
            return
        }
        do {
            try await client.auth.unlinkIdentity(identity)
            await refreshIdentities()
        } catch {
            throw LinkError.underlying(error)
        }
    }

    private func mapLinkError(_ error: Error) -> LinkError {
        let message = error.localizedDescription.lowercased()
        if message.contains("already") && (message.contains("linked") || message.contains("registered") || message.contains("exists")) {
            return .alreadyLinkedToOtherUser
        }
        return .underlying(error)
    }

    // MARK: - Pending provider link (cross-provider auto-link after sign-in)

    /// Called by sign-in handlers (Apple, Email) AFTER successful sign-in to
    /// drain any provider tokens stashed during a blocked cross-provider
    /// sign-in attempt. Auto-links the stashed provider to the now-current
    /// user; success → toast, error → toast pointing user at Settings.
    ///
    /// No-op when `pendingProviderLink` is nil. Self-clearing so concurrent
    /// callers can't double-link.
    func consumePendingLink() async {
        guard let pending = pendingProviderLink else { return }
        pendingProviderLink = nil  // clear early — double-link guard

        do {
            switch pending.provider {
            case "google":
                try await linkGoogleIdentity(
                    idToken: pending.idToken,
                    accessToken: pending.accessToken,
                    nonce: pending.rawNonce
                )
                ToastManager.shared.success("Google added to your account")
            default:
                // Apple/email pending-link cases not implemented yet — the
                // pending state is only ever set by AuthView's Google handler
                // today. Add cases here if/when other providers need the same
                // "ask to merge" flow.
                break
            }
        } catch LinkError.alreadyLinked {
            ToastManager.shared.success("Google is already on your account")
        } catch LinkError.alreadyLinkedToOtherUser {
            // The stashed Google tokens are for an account that's now linked
            // to a DIFFERENT Carry user (rare race — e.g. another device
            // beat us to it). Don't bind it to the wrong user; tell them.
            ToastManager.shared.error("Google is already on a different Carry account.")
        } catch {
            ToastManager.shared.error("Couldn't add Google. Add it from Settings → Sign-in methods.")
        }
    }

    // MARK: - Email Sign-Up / Sign-In

    /// Creates a new account. With email confirmation required (Supabase dashboard
    /// setting), `signUp` returns a user but no session — the user must click the
    /// confirmation link before they can sign in. We surface that as
    /// `emailConfirmationPending` so the UI can show a "Check your email" state.
    ///
    /// `firstName` / `lastName` are optional; when provided they're written straight
    /// into the profile so onboarding can skip the name step (mirrors the Apple
    /// flow at `signInWithApple`). Email is also stored on the profile row.
    func signUpWithEmail(
        email: String,
        password: String,
        firstName: String? = nil,
        lastName: String? = nil
    ) async throws {
        // Pass first/last as Supabase user_metadata so it survives the email
        // round-trip — when confirmation is required the user has no session
        // and RLS would block a direct profile update. After they tap the
        // email link, `handleAuthCallback` reads metadata and writes profile.
        let trimmedFirst = firstName?.trimmingCharacters(in: .whitespaces) ?? ""
        let trimmedLast = lastName?.trimmingCharacters(in: .whitespaces) ?? ""
        var metadata: [String: AnyJSON] = [:]
        if !trimmedFirst.isEmpty { metadata["first_name"] = .string(trimmedFirst) }
        if !trimmedLast.isEmpty { metadata["last_name"] = .string(trimmedLast) }

        let response: AuthResponse
        do {
            response = try await client.auth.signUp(
                email: email,
                password: password,
                data: metadata.isEmpty ? nil : metadata,
                // Trailing `.html` is required because the host (DreamHost / Apache)
                // doesn't auto-resolve extensionless URLs — `/auth/confirm` 404s.
                // The AASA `/auth/*` glob still matches, so iOS Universal Links work.
                redirectTo: URL(string: "https://carryapp.site/auth/confirm.html")
            )
        } catch {
            // Server-side dedup trigger (migration 20260515000000) may raise
            // EMAIL_ALREADY_REGISTERED: <provider> if a user with this email
            // already exists under a different sign-in method.
            throw mapAuthSignupError(error)
        }

        if response.session == nil {
            throw AuthError.emailConfirmationPending
        }

        // Confirmation OFF path: session exists immediately, write profile now.
        var update = ProfileUpdate()
        update.email = email
        if !trimmedFirst.isEmpty, !trimmedLast.isEmpty {
            let display = "\(trimmedFirst) \(trimmedLast)"
            update.firstName = trimmedFirst
            update.lastName = trimmedLast
            update.displayName = display
            update.initials = "\(trimmedFirst.prefix(1))\(trimmedLast.prefix(1))".uppercased()
        }
        _ = try? await client.from("profiles")
            .update(update)
            .eq("id", value: response.user.id.uuidString)
            .execute()

        await finishProviderSignIn(userId: response.user.id, providerLabel: "email")
    }

    func signInWithEmail(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        await finishProviderSignIn(userId: session.user.id, providerLabel: "email")
    }

    /// Exchange a Supabase auth-callback URL for a session, then run the
    /// post-auth wrap-up. Called from `CarryApp.handleIncomingURL` when the
    /// user taps the confirmation link in their email and iOS routes the
    /// Universal Link back into the app.
    ///
    /// Backfills first/last name from `user_metadata` (set during sign-up)
    /// when the profile row is still empty — this is the primary path on
    /// projects where email confirmation is enabled, since the sign-up call
    /// returns no session and we couldn't write the profile then.
    func handleAuthCallback(url: URL) async throws {
        let session = try await client.auth.session(from: url)
        let userId = session.user.id

        let metadata = session.user.userMetadata
        let firstFromMeta = metadata["first_name"]?.stringValue ?? ""
        let lastFromMeta = metadata["last_name"]?.stringValue ?? ""

        if !firstFromMeta.isEmpty, !lastFromMeta.isEmpty {
            await loadProfile(userId: userId)
            let profileMissingName = (currentUser?.firstName.isEmpty ?? true)
            if profileMissingName {
                var update = ProfileUpdate()
                update.email = session.user.email
                update.firstName = firstFromMeta
                update.lastName = lastFromMeta
                update.displayName = "\(firstFromMeta) \(lastFromMeta)"
                update.initials = "\(firstFromMeta.prefix(1))\(lastFromMeta.prefix(1))".uppercased()
                _ = try? await client.from("profiles")
                    .update(update)
                    .eq("id", value: userId.uuidString)
                    .execute()
            }
        }

        await finishProviderSignIn(userId: userId, providerLabel: "email")
    }

    func sendPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(
            email,
            redirectTo: URL(string: "https://carryapp.site/reset")
        )
    }

    // MARK: - Dev Skip (bypass auth for testing)

    #if DEBUG
    func skipAuth() {
        isAuthenticated = true
        isOnboarded = true
        isNewUser = true  // auto-opens profile sheet on MainTabView
        currentUser = nil
    }
    #endif

    // MARK: - Onboarding

    /// Persist the user's onboarding data. Throws on failure so the caller can
    /// show a retry — we do NOT mark onboarded until the save confirms, to avoid
    /// a race where the profiles row stays at DB defaults (e.g. handicap=0.0)
    /// while the user is marked complete and navigates away.
    func completeOnboarding(
        firstName: String,
        lastName: String,
        username: String?,
        ghinNumber: String?,
        handicap: Double,
        photo: UIImage? = nil,
        homeClub: String? = nil,
        homeClubId: Int? = nil,
        isClubMember: Bool = true,
        phone: String? = nil
    ) async throws {
        let displayName = firstName  // First name only for scorecard/pills
        let firstI = String(firstName.prefix(1)).uppercased()
        let lastI = String(lastName.prefix(1)).uppercased()
        let initials = lastI.isEmpty ? String(firstName.prefix(2)).uppercased() : "\(firstI)\(lastI)"

        if isAuthenticated {
            // Real auth'd user — persist to Supabase and AWAIT so we throw
            // on failure rather than silently dropping the update.
            // Note: we branch on `isAuthenticated` (not currentUser != nil)
            // because `currentUser` may briefly be nil during onboarding
            // while the initial profile fetch is in flight. `updateProfile`
            // now handles that case by resolving the userId from the session.
            var avatarUrl: String? = nil
            if let photo = photo {
                avatarUrl = try await uploadAvatar(photo)
            }

            try await updateProfile(ProfileUpdate(
                firstName: firstName,
                lastName: lastName,
                username: username?.lowercased(),
                displayName: displayName,
                initials: initials,
                color: "#BCF0B5",
                avatar: "🏌️",
                handicap: handicap,
                ghinNumber: ghinNumber,
                homeClub: homeClub,
                homeClubId: homeClubId,
                avatarUrl: avatarUrl,
                isClubMember: isClubMember,
                phone: phone
            ))

            // Post-save verification — re-read the just-saved profile state
            // (updateProfile calls loadProfile internally, which writes to
            // currentUser). If the handicap we just wrote doesn't match
            // the handicap the server now reports, something went wrong
            // silently (0 rows affected, stale cache, etc.) — throw so the
            // caller can surface a retry instead of stranding the user at
            // an unintended handicap.
            guard let savedHandicap = currentUser?.handicap else {
                throw AuthError.profileSaveVerificationFailed
            }
            if abs(savedHandicap - handicap) > 0.05 {
                throw AuthError.profileSaveVerificationFailed
            }
        } else {
            // No Supabase session (dev/debug) — create a local profile
            currentUser = ProfileDTO(
                id: UUID(),
                firstName: firstName,
                lastName: lastName,
                username: username?.lowercased(),
                displayName: displayName,
                initials: initials,
                color: "#BCF0B5",
                avatar: "🏌️",
                handicap: handicap,
                ghinNumber: ghinNumber,
                homeClub: homeClub,
                homeClubId: homeClubId,
                avatarUrl: nil,
                email: nil,
                isClubMember: isClubMember,
                createdAt: Date(),
                updatedAt: nil
            )
        }

        // Only mark onboarded AFTER the persist succeeded.
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        isOnboarded = true
        isNewUser = true

        // Fire welcome email. Failure must not block onboarding — we log and continue.
        if isAuthenticated {
            Task { await sendWelcomeEmail(firstName: firstName) }
        }
    }

    // MARK: - Welcome email

    func sendWelcomeEmail(firstName: String) async {
        struct Body: Encodable { let firstName: String }
        do {
            try await client.functions.invoke(
                "send-welcome-email",
                options: FunctionInvokeOptions(body: Body(firstName: firstName))
            )
            Analytics.welcomeEmailSent()
        } catch {
            print("Welcome email failed (non-blocking): \(error)")
            Analytics.welcomeEmailFailed(reason: String(describing: error))
        }
    }

    // MARK: - Username

    func checkUsernameAvailability(_ username: String) async -> Bool {
        // Race the actual check against a 3-second timeout
        // so the UI never gets stuck if Supabase is unreachable.
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    let result: Bool = try await self.client.rpc("is_username_available", params: ["uname": username.lowercased()])
                        .execute()
                        .value
                    return result
                } catch {
                    do {
                        let profiles: [ProfileDTO] = try await self.client.from("profiles")
                            .select()
                            .eq("username", value: username.lowercased())
                            .limit(1)
                            .execute()
                            .value
                        return profiles.isEmpty
                    } catch {
                        return true
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return true // timeout — assume available
            }
            // First to finish wins
            let result = await group.next() ?? true
            group.cancelAll()
            return result
        }
    }

    // MARK: - Sign Out

    func signOut() async throws {
        try await client.auth.signOut()
        await MainActor.run {
            isAuthenticated = false
            isOnboarded = false
            isNewUser = false
            currentUser = nil
            identities = []
        }
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        do {
            try await client.rpc("delete_user_account").execute()
        } catch {
            #if DEBUG
            print("[AuthService] deleteAccount failed: \(error)")
            #endif
            throw error
        }
        // Sign out the session
        try? await client.auth.signOut()
        // Clear local state on main thread
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "onboardingCompleted")
            isAuthenticated = false
            isOnboarded = false
            isNewUser = false
            currentUser = nil
            identities = []
        }
    }

    // MARK: - Profile

    private func loadProfile(userId: UUID) async {
        do {
            let profile: ProfileDTO = try await client.from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            currentUser = profile
        } catch {
            #if DEBUG
            print("Failed to load profile: \(error)")
            #endif
            // Profile doesn't exist (deleted account re-login) — create a blank one
            do {
                let email = try? await client.auth.session.user.email
                try await client.from("profiles")
                    .insert([
                        "id": userId.uuidString,
                        "display_name": "Player",
                        "initials": "P",
                        "email": email ?? ""
                    ])
                    .execute()
                // Reload after creation
                let profile: ProfileDTO = try await client.from("profiles")
                    .select()
                    .eq("id", value: userId.uuidString)
                    .single()
                    .execute()
                    .value
                currentUser = profile
                #if DEBUG
                print("[AuthService] Created new profile for returning user \(userId)")
                #endif
            } catch {
                #if DEBUG
                print("[AuthService] Failed to create profile: \(error)")
                #endif
            }
        }
    }

    func uploadAvatar(_ image: UIImage) async throws -> String {
        guard isAuthenticated, let userId = currentUser?.id else {
            return ""
        }
        guard let data = image.jpegData(compressionQuality: 0.7) else { throw AuthError.missingToken }

        let path = "\(userId.uuidString)/avatar.jpg"

        // Try upload with upsert, fall back to update if file exists
        do {
            try await client.storage.from("avatars").upload(
                path,
                data: data,
                options: .init(contentType: "image/jpeg", upsert: true)
            )
        } catch {
            #if DEBUG
            print("[Photo] Upload failed, trying update: \(error)")
            #endif
            // File may already exist — try update instead
            try await client.storage.from("avatars").update(
                path,
                data: data,
                options: .init(contentType: "image/jpeg", upsert: true)
            )
        }

        // Get public URL with cache-busting timestamp
        let baseUrl = try client.storage.from("avatars").getPublicURL(path: path)
        let urlWithCacheBust = "\(baseUrl.absoluteString)?t=\(Int(Date().timeIntervalSince1970))"
        return urlWithCacheBust
    }

    func updateProfile(_ update: ProfileUpdate) async throws {
        // Dev/debug (no auth) → apply locally. Not expected in production.
        guard isAuthenticated else {
            applyLocalProfileUpdate(update)
            return
        }

        // Resolve userId. Prefer the loaded profile; fall back to the
        // session when `currentUser` hasn't finished loading yet. This
        // closes an onboarding race where the profile fetch is still in
        // flight when the user taps Finish — previously the update fell
        // through to the local-only path and was silently discarded, so
        // the DB handicap stayed at the trigger default of 0.0.
        let userId: UUID
        if let id = currentUser?.id {
            userId = id
        } else {
            do {
                let session = try await client.auth.session
                userId = session.user.id
            } catch {
                // No session despite isAuthenticated == true (shouldn't
                // happen). Fall back to local-only to preserve prior
                // behavior rather than crashing.
                applyLocalProfileUpdate(update)
                return
            }
        }

        try await client.from("profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        await loadProfile(userId: userId)
    }

    /// Apply profile updates locally (dev mode fallback when no auth)
    private func applyLocalProfileUpdate(_ update: ProfileUpdate) {
        guard var user = currentUser else { return }
        if let v = update.firstName { user.firstName = v }
        if let v = update.lastName { user.lastName = v }
        if let v = update.displayName { user.displayName = v }
        if let v = update.initials { user.initials = v }
        if let v = update.handicap { user.handicap = v }
        if let v = update.homeClub { user.homeClub = v }
        if let v = update.homeClubId { user.homeClubId = v }
        if let v = update.avatarUrl { user.avatarUrl = v.isEmpty ? nil : v }
        if let v = update.ghinNumber { user.ghinNumber = v }
        if let v = update.isClubMember { user.isClubMember = v }
        currentUser = user
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case missingToken
    case profileSaveVerificationFailed
    case emailConfirmationPending
    /// Raised when the server-side `check_email_dedup_on_signup` trigger
    /// rejects a new `auth.users` insert because another account already
    /// owns this email under a different provider. `provider` is the
    /// existing provider label (`apple`/`google`/`email`) so the UI can
    /// tell the user which sign-in to use instead. See migration
    /// `20260515000000_dedupe_email_on_signup.sql`.
    case emailAlreadyRegistered(provider: String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Missing identity token from sign-in"
        case .profileSaveVerificationFailed:
            return "Couldn't confirm your profile was saved. Please try again."
        case .emailConfirmationPending:
            return nil
        case .emailAlreadyRegistered(let provider):
            switch provider {
            case "apple":
                return "An account already exists for this email with Apple Sign-In. Please sign in with Apple instead."
            case "google":
                return "An account already exists for this email with Google. Please sign in with Google instead."
            case "email":
                return "An account already exists for this email. Please sign in with your password instead."
            default:
                return "An account already exists for this email. Please sign in with the provider you used originally."
            }
        }
    }
}

// MARK: - Pending provider link

/// Stash for OIDC provider tokens captured during a sign-in attempt that was
/// blocked by the server-side email dedupe trigger. The UI uses this to
/// orchestrate the "Ask to merge" flow: detect collision → prompt user → run
/// existing-provider sign-in → AuthService.consumePendingLink() auto-links the
/// stashed provider to the now-authenticated user.
///
/// Held as `@Published var pendingProviderLink` on `AuthService`.
struct PendingProviderLink {
    /// The blocked provider's label as Supabase reports it (`google` today;
    /// `apple` / `email` reserved for future expansion to those flows).
    let provider: String

    /// ID token issued by the provider during the blocked sign-in attempt.
    /// Reused at link time. Provider ID tokens are typically valid ~1 hour;
    /// the link should happen within seconds of the block, well within that
    /// window.
    let idToken: String

    /// Provider access token, when available. Optional because Google ID-token
    /// sign-in works with or without it; carried through for symmetry with
    /// the original sign-in call.
    let accessToken: String?

    /// Raw OIDC nonce that was used for the blocked sign-in. MUST match what
    /// the ID token's `nonce` claim hashes to — Supabase verifies at link time
    /// the same way it does at sign-in time.
    let rawNonce: String

    /// Provider the user's existing account is on (`apple` / `google` / `email`).
    /// Drives the user-facing copy in the link prompt ("sign in with Apple"
    /// vs "sign in with your password").
    let existingProvider: String
}

// MARK: - Server error mapping
//
// Pure function (no `self`) so it stays test-friendly. Reads the trigger's
// raise message (format: "EMAIL_ALREADY_REGISTERED: <provider>") out of
// whatever wrapping Supabase puts around it and re-throws as the typed
// `AuthError.emailAlreadyRegistered`. Other errors pass through unchanged.
func mapAuthSignupError(_ error: Error) -> Error {
    // TEMP DEBUG: dump everything so we can see what Supabase actually hands
    // us when a Postgres BEFORE INSERT trigger raises EXCEPTION. Remove once
    // mapAuthSignupError's parsing is confirmed correct.
    NSLog("‼️AUTHDEBUG mapAuthSignupError CALLED type=%@", String(describing: type(of: error)))
    NSLog("‼️AUTHDEBUG localizedDescription: %@", error.localizedDescription)
    NSLog("‼️AUTHDEBUG reflect: %@", String(reflecting: error))
    let nsErr = error as NSError
    NSLog("‼️AUTHDEBUG nsError domain=%@ code=%d userInfo=%@", nsErr.domain, nsErr.code, "\(nsErr.userInfo)")

    let msg = error.localizedDescription
    let marker = "EMAIL_ALREADY_REGISTERED:"
    guard let range = msg.range(of: marker) else { return error }
    let tail = msg[range.upperBound...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
    // Take the first letter-only run — the trigger emits one of
    // apple / google / email. Defensive against trailing punctuation
    // or JSON escaping that Supabase might wrap the payload in.
    let provider = tail.prefix { $0.isLetter }
    return AuthError.emailAlreadyRegistered(provider: String(provider))
}
