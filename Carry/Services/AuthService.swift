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

    /// A profile is valid for skipping onboarding if it has a real display name.
    /// If the profile exists in Supabase with a valid name, the user has already onboarded
    /// (possibly on another device or before an app reinstall).
    private var hasValidProfile: Bool {
        guard let profile = currentUser else { return false }
        let name = profile.displayName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty && name != "Player" {
            // Profile exists in Supabase — restore the onboarding flag
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
            // new users get the prompt during onboarding's "Enable Notifications" step)
            if isOnboarded && UserDefaults.standard.bool(forKey: "disclaimerAccepted") {
                NotificationService.shared.requestPermissionAndRegister()
            }
        } catch {
            isAuthenticated = false
            #if !DEBUG
            currentUser = nil
            #endif
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

        await loadProfile(userId: session.user.id)
        isAuthenticated = true

        // Identify user in PostHog
        if let profile = currentUser {
            PostHogSDK.shared.identify(session.user.id.uuidString, userProperties: [
                "name": profile.displayName,
                "handicap": profile.handicap
            ])
        }
        PostHogSDK.shared.capture("user_signed_in")

        // New user: profile exists but default avatar/color = hasn't customized yet
        if let profile = currentUser {
            let hasName = !profile.displayName.trimmingCharacters(in: .whitespaces).isEmpty && profile.displayName != "Player"
            isNewUser = !hasName
        }

        // New users always go through onboarding (photo, handicap, club)
        // even if Apple provided their name
        isOnboarded = isNewUser ? false : hasValidProfile

        // Only register for push if already onboarded — new users get
        // the system prompt during onboarding's "Enable Notifications" step
        if isOnboarded {
            NotificationService.shared.requestPermissionAndRegister()
        }
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

    func completeOnboarding(
        firstName: String,
        lastName: String,
        username: String?,
        ghinNumber: String?,
        handicap: Double,
        photo: UIImage? = nil,
        homeClub: String? = nil,
        homeClubId: Int? = nil,
        isClubMember: Bool = true
    ) {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        isOnboarded = true
        isNewUser = true

        let displayName = firstName  // First name only for scorecard/pills
        let firstI = String(firstName.prefix(1)).uppercased()
        let lastI = String(lastName.prefix(1)).uppercased()
        let initials = lastI.isEmpty ? String(firstName.prefix(2)).uppercased() : "\(firstI)\(lastI)"

        // If we have a real user, persist to Supabase
        if currentUser != nil {
            Task {
                do {
                    // Upload avatar photo if provided
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
                        isClubMember: isClubMember
                    ))
                } catch {
                    #if DEBUG
                    print("Failed to save onboarding profile: \(error)")
                    #endif
                }
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
        guard isAuthenticated, let userId = currentUser?.id else {
            // Dev mode: apply changes locally so profile edits work without auth
            applyLocalProfileUpdate(update)
            return
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

    var errorDescription: String? {
        switch self {
        case .missingToken: return "Missing identity token from Apple Sign-In"
        }
    }
}
