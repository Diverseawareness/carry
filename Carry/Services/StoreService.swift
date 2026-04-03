import StoreKit
import SwiftUI

@MainActor
final class StoreService: ObservableObject {
    @Published var isPremium: Bool = false
    @Published var products: [Product] = []
    @Published var isLoading: Bool = false

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

    func fetchProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let storeProducts = try await Product.products(for: productIDs)
            products = storeProducts.sorted { $0.price > $1.price }
        } catch {
            #if DEBUG
            print("[StoreService] Failed to fetch products: \(error)")
            #endif
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

    func checkEntitlements() async {
        // Auto-grant premium for TestFlight builds
        if isTestFlight {
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

    /// Returns true when the app is installed via TestFlight (sandbox receipt)
    private var isTestFlight: Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return receiptURL.lastPathComponent == "sandboxReceipt"
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? Self.checkVerified(result) {
                    await MainActor.run {
                        self.isPremium = self.productIDs.contains(transaction.productID)
                    }
                    await transaction.finish()
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
