import Foundation
import AuthenticationServices
import Supabase

@MainActor
final class AuthService: ObservableObject {
    @Published var currentUser: ProfileDTO?
    @Published var isAuthenticated = false
    @Published var isOnboarded = false
    @Published var isLoading = true
    @Published var isNewUser = false  // true after first sign-in, triggers profile sheet

    private let client = SupabaseManager.shared.client

    init() {
        Task { await checkSession() }
    }

    // MARK: - Session

    func checkSession() async {
        defer { isLoading = false }
        do {
            let session = try await client.auth.session
            await loadProfile(userId: session.user.id)
            isAuthenticated = true
            isOnboarded = currentUser != nil  // existing users skip onboarding
        } catch {
            isAuthenticated = false
            currentUser = nil
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
            let name = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            if !name.isEmpty {
                update.displayName = name
                update.initials = String(name.prefix(2)).uppercased()
            }
        }

        // Email from Apple credential or Supabase session
        let email = credential.email ?? session.user.email
        if let email, !email.isEmpty {
            update.email = email
        }

        // Apply update if we have anything
        if update.displayName != nil || update.email != nil {
            try? await client.from("profiles")
                .update(update)
                .eq("id", value: session.user.id.uuidString)
                .execute()
        }

        await loadProfile(userId: session.user.id)
        isAuthenticated = true
        isOnboarded = currentUser != nil

        // New user: profile exists but default avatar/color = hasn't customized yet
        if let profile = currentUser {
            let isDefault = profile.avatar == "🏌️" && profile.color == "#D4A017"
            isNewUser = isDefault
        }
    }

    // MARK: - Dev Skip (bypass auth for testing)

    func skipAuth() {
        isAuthenticated = true
        isOnboarded = true
        isNewUser = true  // auto-opens profile sheet on MainTabView
        currentUser = nil
    }

    // MARK: - Onboarding

    func completeOnboarding(name: String, color: String, avatar: String, ghinNumber: String?, handicap: Double) {
        // In production, this would save to Supabase profile.
        // For now, just mark onboarding complete so the gate passes.
        isOnboarded = true

        // If we have a real user, persist to Supabase
        if currentUser != nil {
            Task {
                try? await updateProfile(ProfileUpdate(
                    displayName: name,
                    initials: String(name.prefix(2)).uppercased(),
                    color: color,
                    avatar: avatar,
                    handicap: handicap,
                    ghinNumber: ghinNumber
                ))
            }
        }
    }

    // MARK: - Sign Out

    func signOut() async throws {
        try await client.auth.signOut()
        isAuthenticated = false
        currentUser = nil
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
            print("Failed to load profile: \(error)")
        }
    }

    func updateProfile(_ update: ProfileUpdate) async throws {
        guard let userId = currentUser?.id else { return }
        try await client.from("profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        await loadProfile(userId: userId)
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
