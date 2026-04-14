import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var storeService: StoreService
    @Environment(\.dismiss) var dismiss
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var selectedPlan: PlanType = .annual

    private enum PlanType { case annual, monthly }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Dismiss
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.textSecondary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color.bgSecondary))
                        }
                        .accessibilityLabel("Close")
                        .accessibilityHint("Dismiss the subscription screen")
                    }
                    .padding(.top, 16)
                    .padding(.trailing, 20)

                    // Hero
                    VStack(spacing: 8) {
                        Image("premium-crown")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .padding(.bottom, 4)
                            .accessibilityHidden(true)

                        Text("Go Premium")
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundColor(Color.textPrimary)

                        Text("Unlock the full Carry experience")
                            .font(.system(size: 16))
                            .foregroundColor(Color.textSubtle)
                    }
                    .padding(.top, 8)

                    // Features
                    VStack(alignment: .leading, spacing: 14) {
                        featureRow("Unlimited skins game groups")
                        featureRow("Full round history & winnings")
                        featureRow("All-time season leaderboard")
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 32)

                    // Legal links
                    HStack(spacing: 4) {
                        Link("Terms of Service", destination: URL(string: "https://carryapp.site/terms.html")!)
                        Text("and")
                            .foregroundColor(Color.textSecondary)
                        Link("Privacy Policy", destination: URL(string: "https://carryapp.site/privacy.html")!)
                    }
                    .font(.system(size: 13))
                    .foregroundColor(Color.goldDark)
                    .padding(.top, 32)

                    // Plan cards
                    VStack(spacing: 12) {
                        // Annual
                        planCard(
                            type: .annual,
                            title: "Annual",
                            subtitle: annualSubtitle,
                            detail: "Best value — full season coverage"
                        )

                        // Monthly
                        planCard(
                            type: .monthly,
                            title: "Monthly",
                            subtitle: monthlySubtitle,
                            detail: "Full access, cancel anytime"
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    if storeService.products.isEmpty && !storeService.isLoading {
                        Text("Unable to load subscription options")
                            .font(.system(size: 14))
                            .foregroundColor(Color.textSecondary)
                            .padding(.top, 16)
                    }

                    if storeService.isLoading {
                        ProgressView()
                            .padding(.top, 16)
                    }

                    // Selected plan summary
                    Text(ctaSummary)
                        .font(.system(size: 14))
                        .foregroundColor(Color.textSecondary)
                        .padding(.top, 20)

                    // CTA Button
                    Button {
                        purchaseSelected()
                    } label: {
                        Text("Try It Free")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.textPrimary)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing || storeService.products.isEmpty)
                    .opacity(isPurchasing ? 0.6 : 1)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    if isPurchasing {
                        ProgressView()
                            .padding(.top, 8)
                    }

                    // Auto-renewal disclosure (required by App Store Guideline 3.1.2)
                    Text("Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage in Settings > Apple ID > Subscriptions.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.textDisabled)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 16)

                    // Restore
                    Button {
                        Task { await storeService.restorePurchases() }
                    } label: {
                        Text("Restore Purchases")
                            .font(.system(size: 14))
                            .foregroundColor(Color.textTertiary)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
        }
        .alert("Purchase Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: storeService.isPremium) {
            if storeService.isPremium { dismiss() }
        }
    }

    // MARK: - Plan Card

    private func planCard(type: PlanType, title: String, subtitle: String, detail: String) -> some View {
        let isSelected = selectedPlan == type

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlan = type
            }
        } label: {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color.textPrimary)
                        Text(subtitle)
                            .font(.system(size: 15))
                            .foregroundColor(Color.textTertiary)
                    }
                    Spacer()

                    // Radio
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? Color.goldDark : Color.dividerLight, lineWidth: 2)
                            .frame(width: 26, height: 26)
                        if isSelected {
                            Circle()
                                .fill(Color.goldDark)
                                .frame(width: 26, height: 26)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                Rectangle()
                    .fill(Color.borderFaint)
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                HStack {
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundColor(Color.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.goldDark : Color.bgSecondary, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) plan, \(subtitle)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Double tap to select this plan")
    }

    // MARK: - Feature Row

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(Color.goldDark)
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(Color(hexString: "#3A3A3C"))
        }
    }

    // MARK: - Computed Text

    private var annualSubtitle: String {
        if let product = storeService.annualProduct {
            return "7 days free, then \(product.displayPrice)/year"
        }
        return "7 days free, then $29.99/year"
    }

    private var monthlySubtitle: String {
        if let product = storeService.monthlyProduct {
            return "7 days free, then \(product.displayPrice)/month"
        }
        return "7 days free, then $4.99/month"
    }

    private var ctaSummary: String {
        if selectedPlan == .annual {
            return annualSubtitle
        } else {
            return monthlySubtitle
        }
    }

    // MARK: - Purchase

    private func purchaseSelected() {
        let product: Product?
        if selectedPlan == .annual {
            product = storeService.annualProduct
        } else {
            product = storeService.monthlyProduct
        }
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        Task {
            do {
                try await storeService.purchase(product)
            } catch {
                errorMessage = error.localizedDescription
            }
            isPurchasing = false
        }
    }
}
