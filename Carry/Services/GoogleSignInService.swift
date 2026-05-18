import Foundation
import UIKit

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

/// Thin wrapper around GoogleSignIn-iOS so AuthView doesn't deal with the SDK directly.
///
/// `#if canImport(GoogleSignIn)` lets the project keep compiling before the SPM
/// dependency is added — tapping the Google button just throws `.notConfigured`
/// until `https://github.com/google/GoogleSignIn-iOS` is added via SPM and the
/// `GIDClientID` is set in Info.plist.
enum GoogleSignInService {
    enum Failure: LocalizedError {
        case notConfigured
        case missingIDToken
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Google Sign-In isn't set up yet."
            case .missingIDToken: return "Google didn't return a valid token."
            case .cancelled: return nil
            }
        }
    }

    struct Tokens {
        let idToken: String
        let accessToken: String?
        /// Raw nonce used for this sign-in. Forward to Supabase's
        /// `signInWithIdToken(...nonce:)` so the server-side hash comparison
        /// matches the `nonce` claim Google embedded in the ID token. Without
        /// this, Supabase rejects with "Passed nonce and nonce in id_token
        /// should either both exist or not."
        let rawNonce: String
    }

    @MainActor
    static func signIn(presenting: UIViewController) async throws -> Tokens {
        #if canImport(GoogleSignIn)
        // OIDC nonce flow: generate a raw nonce, pass the SHA256 hash to
        // Google (Google embeds the hash in the ID token's `nonce` claim),
        // then return the raw value so the caller can hand it to Supabase
        // for the matching server-side check.
        let rawNonce = AuthNonce.randomString()
        let hashedNonce = AuthNonce.sha256Hex(rawNonce)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenting,
                hint: nil,
                additionalScopes: nil,
                nonce: hashedNonce
            )
            guard let idToken = result.user.idToken?.tokenString else {
                throw Failure.missingIDToken
            }
            return Tokens(
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString,
                rawNonce: rawNonce
            )
        } catch let error as NSError where error.code == GIDSignInError.canceled.rawValue {
            throw Failure.cancelled
        }
        #else
        throw Failure.notConfigured
        #endif
    }
}
