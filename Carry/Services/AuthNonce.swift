import CryptoKit
import Foundation

/// Nonce utilities for OIDC-style sign-in flows (Google, Apple-with-nonce,
/// any provider that uses `signInWithIdToken`).
///
/// Why nonces matter: the provider hashes our nonce (SHA256) and embeds it
/// in the ID token's `nonce` claim. The auth backend (Supabase) re-hashes
/// the raw nonce we send and compares; mismatch = reject. This protects
/// against replay — an attacker can't reuse a captured ID token because the
/// nonce was bound to a one-time client request.
///
/// Flow:
///   1. Caller generates a `randomNonceString()` (the **raw** value).
///   2. Caller passes `sha256(raw)` to the provider SDK (Google/Apple).
///   3. Provider returns an ID token whose `nonce` claim is the SHA256 hash.
///   4. Caller passes the **raw** nonce alongside the ID token to Supabase.
///   5. Supabase re-hashes the raw nonce, compares to the claim, succeeds.
///
/// Skipping nonce on the Supabase side is possible ("Skip nonce checks" toggle
/// in dashboard) but weakens replay protection. Prefer this proper flow.
enum AuthNonce {
    /// Random URL-safe nonce string. Uses `SecRandomCopyBytes` for CSPRNG-grade
    /// entropy then maps each byte to one of 62 alphanumeric chars (no special
    /// chars to avoid percent-encoding edge cases).
    static func randomString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess, "Unable to generate nonce — SecRandomCopyBytes failed (\(status))")
            for byte in randoms where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    /// Returns the SHA256 hash of `input` as a lowercase hex string. This is the
    /// format providers (Google + Apple) expect to embed in the ID token's
    /// `nonce` claim.
    static func sha256Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
