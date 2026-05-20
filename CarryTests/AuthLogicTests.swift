import XCTest
@testable import Carry

/// Unit tests for the pure-function pieces of the auth-v2 surface.
///
/// Out of scope: anything that calls `client.auth.*` (networking),
/// SwiftUI views, and PKCE recovery (requires a real Supabase session).
/// Those live in manual test plans (`docs/test-plan-1.1.0-auth.md`).
final class AuthLogicTests: XCTestCase {

    // MARK: - mapAuthSignupError

    /// Server trigger `check_email_dedup_on_signup` raises
    /// `EMAIL_ALREADY_REGISTERED: <provider>`. Supabase wraps this in an
    /// NSError-like; mapAuthSignupError reads the marker out and re-throws
    /// the typed AuthError. Each provider variant must parse cleanly.
    func testMapAuthSignupError_appleProvider() {
        let upstream = makeSupabaseError("EMAIL_ALREADY_REGISTERED: apple")
        let mapped = mapAuthSignupError(upstream)
        guard case .emailAlreadyRegistered(let provider) = (mapped as? AuthError) else {
            XCTFail("Expected emailAlreadyRegistered, got \(mapped)")
            return
        }
        XCTAssertEqual(provider, "apple")
    }

    func testMapAuthSignupError_googleProvider() {
        let upstream = makeSupabaseError("EMAIL_ALREADY_REGISTERED: google")
        let mapped = mapAuthSignupError(upstream)
        guard case .emailAlreadyRegistered(let provider) = (mapped as? AuthError) else {
            XCTFail("Expected emailAlreadyRegistered, got \(mapped)")
            return
        }
        XCTAssertEqual(provider, "google")
    }

    func testMapAuthSignupError_emailProvider() {
        let upstream = makeSupabaseError("EMAIL_ALREADY_REGISTERED: email")
        let mapped = mapAuthSignupError(upstream)
        guard case .emailAlreadyRegistered(let provider) = (mapped as? AuthError) else {
            XCTFail("Expected emailAlreadyRegistered, got \(mapped)")
            return
        }
        XCTAssertEqual(provider, "email")
    }

    /// Defensive against Supabase wrapping the message in JSON or trailing
    /// punctuation. The parser takes only the first letter-run after the
    /// marker — anything past that must be discarded.
    func testMapAuthSignupError_stripsTrailingPunctuation() {
        let upstream = makeSupabaseError("EMAIL_ALREADY_REGISTERED: apple\"}")
        let mapped = mapAuthSignupError(upstream)
        guard case .emailAlreadyRegistered(let provider) = (mapped as? AuthError) else {
            XCTFail("Expected emailAlreadyRegistered, got \(mapped)")
            return
        }
        XCTAssertEqual(provider, "apple")
    }

    /// Errors without the marker pass through unchanged. Prevents accidental
    /// conversion of unrelated Supabase errors into emailAlreadyRegistered.
    func testMapAuthSignupError_passthroughForUnrelated() {
        let upstream = makeSupabaseError("rate limit exceeded")
        let mapped = mapAuthSignupError(upstream)
        XCTAssertNil(mapped as? AuthError, "Unrelated errors must not become AuthError")
        XCTAssertEqual((mapped as NSError).localizedDescription, "rate limit exceeded")
    }

    /// Empty / whitespace-only marker tail returns an empty provider string
    /// rather than crashing. The default-branch copy in errorDescription
    /// covers this gracefully.
    func testMapAuthSignupError_emptyProviderTail() {
        let upstream = makeSupabaseError("EMAIL_ALREADY_REGISTERED:")
        let mapped = mapAuthSignupError(upstream)
        guard case .emailAlreadyRegistered(let provider) = (mapped as? AuthError) else {
            XCTFail("Expected emailAlreadyRegistered, got \(mapped)")
            return
        }
        XCTAssertEqual(provider, "")
    }

    // MARK: - AuthError.errorDescription

    func testAuthErrorCopy_appleProvider() {
        let desc = AuthError.emailAlreadyRegistered(provider: "apple").errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.contains("Apple"), "Apple copy should mention Apple Sign-In")
    }

    func testAuthErrorCopy_googleProvider() {
        let desc = AuthError.emailAlreadyRegistered(provider: "google").errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.contains("Google"), "Google copy should mention Google")
    }

    func testAuthErrorCopy_emailProvider() {
        let desc = AuthError.emailAlreadyRegistered(provider: "email").errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.contains("password"), "Email copy should mention password")
    }

    /// Defensive default for any future provider label the trigger might
    /// emit — copy stays generic instead of crashing on an unknown case.
    func testAuthErrorCopy_unknownProviderFallsBack() {
        let desc = AuthError.emailAlreadyRegistered(provider: "twitter").errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.contains("already exists"))
    }

    func testAuthErrorCopy_emailConfirmationPendingIsNil() {
        // Intentionally nil — UI suppresses the alert and shows its own
        // "Check your email" state instead. Don't regress this to a string.
        XCTAssertNil(AuthError.emailConfirmationPending.errorDescription)
    }

    // MARK: - AuthNonce.randomString

    /// Default length is 32 chars (matches Google/Apple OIDC recommendations).
    func testRandomString_defaultLength() {
        XCTAssertEqual(AuthNonce.randomString().count, 32)
    }

    func testRandomString_customLength() {
        XCTAssertEqual(AuthNonce.randomString(length: 64).count, 64)
        XCTAssertEqual(AuthNonce.randomString(length: 8).count, 8)
    }

    /// Only base62 chars — no special chars that need percent-encoding
    /// when passed through URL parameters.
    func testRandomString_charsetIsBase62() {
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        let nonce = AuthNonce.randomString(length: 256)
        for char in nonce {
            XCTAssertTrue(allowed.contains(char), "Unexpected char \(char) in nonce")
        }
    }

    /// CSPRNG output: 10 consecutive calls must all be distinct. (Birthday
    /// collision at 32 chars × 62 alphabet is astronomically unlikely.)
    func testRandomString_isRandom() {
        let nonces = (0..<10).map { _ in AuthNonce.randomString() }
        XCTAssertEqual(Set(nonces).count, nonces.count, "Nonces must not collide")
    }

    // MARK: - AuthNonce.sha256Hex

    /// Known SHA-256 vector — `sha256("abc")` = `ba7816bf…f20015ad`.
    /// Locks the encoding (lowercase hex) so we don't accidentally switch
    /// to uppercase or base64 and break Supabase nonce verification.
    func testSha256Hex_knownVector() {
        XCTAssertEqual(
            AuthNonce.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testSha256Hex_isDeterministic() {
        let input = "the-quick-brown-fox-jumps"
        XCTAssertEqual(AuthNonce.sha256Hex(input), AuthNonce.sha256Hex(input))
    }

    func testSha256Hex_emptyString() {
        // sha256("") = e3b0c442…b855
        XCTAssertEqual(
            AuthNonce.sha256Hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testSha256Hex_lengthIs64() {
        XCTAssertEqual(AuthNonce.sha256Hex("any input").count, 64)
    }

    // MARK: - PendingProviderLink

    /// Round-trip the stash that the "Ask to merge" UX uses. If this changes
    /// shape, the Ask flow's consumePendingLink() will silently mismatch.
    func testPendingProviderLink_preservesAllFields() {
        let link = PendingProviderLink(
            provider: "google",
            idToken: "fake-id-token",
            accessToken: "fake-access-token",
            rawNonce: "abc123",
            existingProvider: "apple"
        )
        XCTAssertEqual(link.provider, "google")
        XCTAssertEqual(link.idToken, "fake-id-token")
        XCTAssertEqual(link.accessToken, "fake-access-token")
        XCTAssertEqual(link.rawNonce, "abc123")
        XCTAssertEqual(link.existingProvider, "apple")
    }

    func testPendingProviderLink_allowsNilAccessToken() {
        let link = PendingProviderLink(
            provider: "google",
            idToken: "id",
            accessToken: nil,
            rawNonce: "n",
            existingProvider: "email"
        )
        XCTAssertNil(link.accessToken)
    }

    // MARK: - LinkError.errorDescription

    func testLinkErrorCopy_alreadyLinked() {
        let desc = AuthService.LinkError.alreadyLinked.errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.lowercased().contains("already"))
    }

    func testLinkErrorCopy_alreadyLinkedToOtherUser() {
        let desc = AuthService.LinkError.alreadyLinkedToOtherUser.errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.lowercased().contains("different"))
    }

    /// Critical guard copy — if a user has only one sign-in method, the UI
    /// must tell them they can't unlink it, otherwise they could lock
    /// themselves out.
    func testLinkErrorCopy_lastIdentity() {
        let desc = AuthService.LinkError.lastIdentity.errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.lowercased().contains("can't"))
    }

    // MARK: - Test helpers

    /// Simulates the NSError shape Supabase produces when a Postgres
    /// trigger raises EXCEPTION. The marker lives in localizedDescription.
    private func makeSupabaseError(_ message: String) -> Error {
        NSError(
            domain: "io.supabase",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
