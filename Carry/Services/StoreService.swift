import StoreKit
import SwiftUI

@MainActor
final class StoreService: ObservableObject {
    @Published var isPremium: Bool = false {
        didSet {
            // Sticky flag — once a user has been premium on this device,
            // `hadPremium` stays true forever. Used by the paywall to show
            // "Your Premium trial ended" framing instead of a generic upsell.
            if isPremium && !hadPremium {
                hadPremium = true
                UserDefaults.standard.set(true, forKey: "hadPremium")
            }
        }
    }
    @Published var products: [Product] = []
    @Published var isLoading: Bool = false
    @Published var fetchError: String?

    /// True if this device has ever seen `isPremium = true`. Cached from
    /// UserDefaults on init and kept in sync by `isPremium.didSet`. Read
    /// from SwiftUI bodies without hitting disk.
    @Published private(set) var hadPremium: Bool = UserDefaults.standard.bool(forKey: "hadPremium")

    private let productIDs: Set<String> = [
        "com.diverseawareness.carry.premium.annual",
        "com.diverseawareness.carry.premium.monthly"
    ]

    // MARK: - TestFlight Premium Override
    //
    // ⚠️ TESTFLIGHT-ONLY FLAG — remove before App Store submission ⚠️
    //
    // When true, grants premium to all users running the app with a sandbox receipt
    // (i.e. TestFlight builds). This lets internal/external testers try premium
    // features without paying in sandbox.
    //
    // Sandbox receipts are also what Apple reviewers use — so DO NOT ship to App Store
    // with this on. The plan: keep this on for Build 44 (TestFlight-only), flip to
    // false before archiving Build 45 for App Store.
    //
    // Scoped to !DEBUG so local dev still uses the DebugMenu isPremium toggle.
    private static let grantPremiumInTestFlight = true

    private var transactionListener: Task<Void, Error>?

    init() {
        transactionListener = listenForTransactions()
        Task { await checkEntitlements() }
        Task { await fetchProducts() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Fetch Products

    /// Fetches products from the App Store. Sets `fetchError` on failure so UI can show retry.
    func fetchProducts() async {
        isLoading = true
        fetchError = nil
        defer { isLoading = false }

        do {
            let storeProducts = try await Product.products(for: productIDs)
            guard !storeProducts.isEmpty else {
                fetchError = "No subscription options available right now. Please try again."
                NSLog("[StoreService] Product.products returned empty for IDs: \(productIDs)")
                return
            }
            // Sort annual first (longer period), then monthly. Avoid sorting by price
            // (fragile across regions/currencies).
            products = storeProducts.sorted { a, b in
                a.id.contains("annual") && !b.id.contains("annual")
            }
        } catch {
            fetchError = "Couldn't load subscription options. Check your connection and try again."
            NSLog("[StoreService] Failed to fetch products: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            isPremium = true
            await transaction.finish()
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        try? await AppStore.sync()
        await checkEntitlements()
    }

    // MARK: - Entitlements

    /// Checks current subscription entitlements. Grants premium when a valid transaction
    /// exists. Also grants premium in TestFlight (sandbox) when `grantPremiumInTestFlight`
    /// is true — see the flag's comment above.
    func checkEntitlements() async {
        if shouldForceTestFlightPremium {
            NSLog("[StoreService] TestFlight premium override active — granting premium.")
            isPremium = true
            return
        }

        var foundEntitlement = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? Self.checkVerified(result),
               productIDs.contains(transaction.productID) {
                foundEntitlement = true
                break
            }
        }
        isPremium = foundEntitlement
    }

    /// True only in Release builds with the override flag on.
    /// In DEBUG this always returns false so local dev behaves normally.
    ///
    /// We intentionally DO NOT check `appStoreReceiptURL` here — that URL can be nil
    /// on fresh TestFlight installs until a receipt has been issued, which caused
    /// testers to launch without premium. Flipping `grantPremiumInTestFlight` to
    /// false before App Store archive is the only safeguard needed.
    private var shouldForceTestFlightPremium: Bool {
        #if DEBUG
        return false
        #else
        return Self.grantPremiumInTestFlight
        #endif
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try Self.checkVerified(result)
                    await MainActor.run {
                        // Keep premium true if the TestFlight override is active, otherwise
                        // reflect the real transaction state.
                        if self.shouldForceTestFlightPremium {
                            self.isPremium = true
                        } else {
                            self.isPremium = self.productIDs.contains(transaction.productID)
                        }
                    }
                    await transaction.finish()
                } catch {
                    NSLog("[StoreService] Transaction verification failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Verification

    private nonisolated static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Convenience

    var annualProduct: Product? {
        products.first { $0.id.contains("annual") }
    }

    var monthlyProduct: Product? {
        products.first { $0.id.contains("monthly") }
    }

    #if DEBUG
    /// Debug-only override for previewing the paywall in its two states
    /// (new user vs post-trial). Flips the sticky flag + UserDefaults so
    /// both the in-session view and future launches see the change.
    func _debugSetHadPremium(_ value: Bool) {
        hadPremium = value
        UserDefaults.standard.set(value, forKey: "hadPremium")
    }
    #endif
}

enum StoreError: LocalizedError {
    case failedVerification
    var errorDescription: String? {
        switch self {
        case .failedVerification: return "Transaction verification failed"
        }
    }
}
