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
    }

    @MainActor
    static func signIn(presenting: UIViewController) async throws -> Tokens {
        #if canImport(GoogleSignIn)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
            guard let idToken = result.user.idToken?.tokenString else {
                throw Failure.missingIDToken
            }
            return Tokens(idToken: idToken, accessToken: result.user.accessToken.tokenString)
        } catch let error as NSError where error.code == GIDSignInError.canceled.rawValue {
            throw Failure.cancelled
        }
        #else
        throw Failure.notConfigured
        #endif
    }
}
