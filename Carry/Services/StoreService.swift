import StoreKit
import SwiftUI

@MainActor
final class StoreService: ObservableObject {
    @Published var isPremium: Bool = false
    @Published var products: [Product] = []
    @Published var isLoading: Bool = false
    @Published var fetchError: String?

    private let productIDs: Set<String> = [
        "com.diverseawareness.carry.premium.annual",
        "com.diverseawareness.carry.premium.monthly"
    ]

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

    /// Checks current subscription entitlements. Only grants premium when a valid
    /// transaction exists — no auto-grant based on sandbox/TestFlight. Apple reviewers
    /// test using sandbox accounts and must see the real paywall + purchase flow.
    func checkEntitlements() async {
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

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try Self.checkVerified(result)
                    await MainActor.run {
                        self.isPremium = self.productIDs.contains(transaction.productID)
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
}

enum StoreError: LocalizedError {
    case failedVerification
    var errorDescription: String? {
        switch self {
        case .failedVerification: return "Transaction verification failed"
        }
    }
}
