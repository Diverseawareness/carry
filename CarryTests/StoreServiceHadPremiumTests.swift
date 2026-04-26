import XCTest
@testable import Carry

/// Tests for `StoreService.hadPremium` — the sticky @Published flag that
/// tracks whether the current device has ever observed `isPremium = true`.
///
/// This flag drives the two paywall variants: first-time users see "Go Premium
/// / Try It Free"; anyone with a history of Premium (trial or paid) sees
/// "Premium Trial Ended / Subscribe". Stickiness matters because a user whose
/// trial has expired will flip `isPremium` back to false — but Apple won't
/// grant a second trial on the same Apple ID, so the paywall MUST keep showing
/// the post-trial variant even after entitlement drops.
@MainActor
final class StoreServiceHadPremiumTests: XCTestCase {

    private let hadPremiumKey = "hadPremium"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: hadPremiumKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: hadPremiumKey)
        try await super.tearDown()
    }

    // MARK: - Initial state

    func testFreshInstallStartsWithHadPremiumFalse() {
        let service = StoreService()
        XCTAssertFalse(service.hadPremium, "Fresh install (no UserDefaults value) must default to false")
    }

    func testInitReadsExistingUserDefaultsValue() {
        UserDefaults.standard.set(true, forKey: hadPremiumKey)
        let service = StoreService()
        XCTAssertTrue(service.hadPremium, "hadPremium must be rehydrated from UserDefaults on init")
    }

    // MARK: - Flip behavior

    func testIsPremiumTrueFlipsHadPremiumTrue() {
        let service = StoreService()
        XCTAssertFalse(service.hadPremium)
        service.isPremium = true
        XCTAssertTrue(service.hadPremium, "isPremium = true must flip hadPremium to true via didSet")
    }

    func testFlipPersistsToUserDefaults() {
        let service = StoreService()
        service.isPremium = true
        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: hadPremiumKey),
            "hadPremium flip must be persisted to UserDefaults so it survives app restarts"
        )
    }

    // MARK: - Stickiness

    /// The core invariant: once hadPremium is true, setting isPremium = false
    /// must NOT flip it back. This is what makes the paywall keep showing
    /// "Premium Trial Ended / Subscribe" after the trial expires.
    func testHadPremiumIsStickyAfterIsPremiumFlipsBackToFalse() {
        let service = StoreService()
        service.isPremium = true
        XCTAssertTrue(service.hadPremium)

        service.isPremium = false
        XCTAssertTrue(
            service.hadPremium,
            "hadPremium must remain true after isPremium flips back — trial-ended users can't get a second trial"
        )
    }

    func testHadPremiumRemainsStickyAcrossMultipleFlips() {
        let service = StoreService()

        // Simulate: trial starts → trial ends → user resubscribes → cancels
        service.isPremium = true   // trial started
        service.isPremium = false  // trial ended
        service.isPremium = true   // resubscribed
        service.isPremium = false  // cancelled

        XCTAssertTrue(service.hadPremium, "hadPremium must survive multiple isPremium flips")
    }

    // MARK: - Debug setter

    #if DEBUG
    func testDebugSetterCanSetTrue() {
        let service = StoreService()
        service._debugSetHadPremium(true)
        XCTAssertTrue(service.hadPremium)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: hadPremiumKey))
    }

    /// The debug setter is the only path that can flip hadPremium back to
    /// false (e.g. previewing the "Go Premium / Try It Free" variant in the
    /// Debug menu). Production code never resets it — Apple's intro offer
    /// eligibility is the real source of truth and is one-way.
    func testDebugSetterCanResetToFalse() {
        let service = StoreService()
        service.isPremium = true
        XCTAssertTrue(service.hadPremium)

        service._debugSetHadPremium(false)
        XCTAssertFalse(service.hadPremium)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: hadPremiumKey))
    }
    #endif
}
