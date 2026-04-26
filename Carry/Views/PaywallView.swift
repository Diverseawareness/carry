import SwiftUI
import StoreKit

/// Why the paywall was opened. Drives the contextual subtitle line —
/// "Starting rounds is a Premium feature" vs. a generic "Go Premium" —
/// without branching the whole view. When `hadPremium` is true the hero
/// title also flips to "Your Premium trial ended" so post-trial users see
/// the reassuring framing we designed instead of a first-time upsell.
enum PaywallTrigger {
    case startRound
    case createGroup
    case scoreRound
    case manageGroup
    case allTimeLeaderboard
    case general

    /// One-line context shown just under the hero title.
    var contextLine: String {
        switch self {
        case .startRound:          return "Starting rounds is a Premium feature"
        case .createGroup:         return "Recurring Skins Groups are Premium"
        case .scoreRound:          return "Scoring rounds is a Premium feature"
        case .manageGroup:         return "Managing groups is a Premium feature"
        case .allTimeLeaderboard:  return "All-time leaderboards are a Premium feature"
        case .general:             return ""
        }
    }
}

struct PaywallView: View {
    @EnvironmentObject var storeService: StoreService
    @Environment(\.dismiss) var dismiss
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var selectedPlan: PlanType = .annual

    /// Why this paywall was opened. Omit for the generic "Go Premium" upsell.
    var trigger: PaywallTrigger = .general

    private enum PlanType { case annual, monthly }

    /// Hero title — flips to "Your Premium trial ended" for users who were
    /// previously premium, regardless of which action triggered the sheet.
    /// This is the main UX promise of the v2 free tier: post-trial users
    /// get the reassuring framing (you had this, you can have it back)
    /// instead of a cold first-time pitch.
    private var heroTitle: String {
        storeService.hadPremium ? "Premium Trial Ended" : "Go Premium"
    }

    /// CTA button label flips for post-trial users — "Try It Free" would
    /// be false advertising since Apple won't grant a second trial on the
    /// same Apple ID.
    private var ctaButtonLabel: String {
        storeService.hadPremium ? "Subscribe" : "Try It Free"
    }

    /// Auto-renewal disclosure (required by App Store Guideline 3.1.2).
    /// Post-trial users see shorter copy without the trial-conversion line.
    private var autoRenewalDisclosure: String {
        if storeService.hadPremium {
            return "Payment will be charged to your Apple ID at confirmation of purchase. Your subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Manage in Settings > Apple ID > Subscriptions."
        }
        return "Payment will be charged to your Apple ID at confirmation of purchase. Your 30-day free trial converts to a paid subscription that renews automatically unless cancelled at least 24 hours before the end of the current period. Manage in Settings > Apple ID > Subscriptions."
    }

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

                    // Hero — title flips based on hadPremium so returning
                    // users see "Your Premium trial ended" framing instead
                    // of the first-time pitch. Contextual line appears only
                    // when a specific trigger was set.
                    VStack(spacing: 8) {
                        Image("premium-crown")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .padding(.bottom, 4)
                            .accessibilityHidden(true)

                        Text(heroTitle)
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundColor(Color.textPrimary)
                            .multilineTextAlignment(.center)

                        if !trigger.contextLine.isEmpty {
                            Text(trigger.contextLine)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.top, 8)

                    // Features. Trial-ended users get an intro line and a
                    // neutral "Skins Game Groups" label (they already know
                    // it's unlimited from their trial); first-time users
                    // see the feature list cold, so we lead with "Unlimited".
                    // For trial-ended users the block is horizontally
                    // centered on the sheet with rows left-aligned inside
                    // (checkmarks line up); first-time users get the
                    // traditional left-aligned feature checklist.
                    Group {
                        if storeService.hadPremium {
                            HStack {
                                Spacer()
                                // Outer VStack (default .center alignment) centers
                                // "Keep your:" above the inner VStack. Inner VStack
                                // (alignment .leading) keeps the checkmark rows
                                // left-aligned together. Net result: block centers
                                // on the sheet, header centers above, rows align.
                                VStack(spacing: 14) {
                                    Text("Keep your:")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(Color.textPrimary)
                                        .padding(.bottom, 2)
                                    VStack(alignment: .leading, spacing: 14) {
                                        featureRow("Skins Game Groups")
                                        featureRow("Full round history & winnings")
                                        featureRow("All-time season leaderboard")
                                    }
                                }
                                Spacer()
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                featureRow("Unlimited skins game groups")
                                featureRow("Full round history & winnings")
                                featureRow("All-time season leaderboard")
                            }
                            .padding(.horizontal, 36)
                        }
                    }
                    .padding(.top, 24)

                    // Extras
                    Text("+ Custom handicap % and Skins Carries")
                        .font(.system(size: 13))
                        .foregroundColor(Color.textSecondary)
                        .padding(.top, 14)

                    // Legal links
                    HStack(spacing: 4) {
                        Link("Terms of Service", destination: URL(string: "https://carryapp.site/terms.html")!)
                        Text("and")
                            .foregroundColor(Color.textSecondary)
                        Link("Privacy Policy", destination: URL(string: "https://carryapp.site/privacy.html")!)
                    }
                    .font(.system(size: 13))
                    .foregroundColor(Color.goldDark)
                    .padding(.top, 20)

                    // Plan cards — only shown once products have loaded
                    if !storeService.products.isEmpty {
                        VStack(spacing: 12) {
                            if storeService.annualProduct != nil {
                                planCard(
                                    type: .annual,
                                    title: "Annual",
                                    subtitle: annualSubtitle,
                                    detail: "Best value — full season coverage"
                                )
                            }
                            if storeService.monthlyProduct != nil {
                                planCard(
                                    type: .monthly,
                                    title: "Monthly",
                                    subtitle: monthlySubtitle,
                                    detail: "Full access, cancel anytime"
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }

                    // Loading state
                    if storeService.isLoading {
                        ProgressView()
                            .padding(.top, 24)
                        Text("Loading subscription options…")
                            .font(.system(size: 14))
                            .foregroundColor(Color.textSecondary)
                            .padding(.top, 8)
                    }

                    // Error state with retry
                    if !storeService.isLoading && storeService.products.isEmpty {
                        VStack(spacing: 12) {
                            Text(storeService.fetchError ?? "Unable to load subscription options.")
                                .font(.system(size: 14))
                                .foregroundColor(Color.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)

                            Button {
                                Task { await storeService.fetchProducts() }
                            } label: {
                                Text("Try Again")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.textPrimary))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 24)
                    }

                    // CTA (only when products loaded). The price/trial
                    // context already lives on the plan card, so we skip
                    // a duplicate summary line above the button.
                    if !storeService.products.isEmpty {
                        Button {
                            purchaseSelected()
                        } label: {
                            Text(ctaButtonLabel)
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
                        .disabled(isPurchasing)
                        .opacity(isPurchasing ? 0.6 : 1)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }

                    if isPurchasing {
                        ProgressView()
                            .padding(.top, 8)
                    }

                    // Auto-renewal disclosure (required by App Store Guideline 3.1.2).
                    // Copy adapts to trial-available vs post-trial state.
                    Text(autoRenewalDisclosure)
                        .font(.system(size: 11))
                        .foregroundColor(Color.textDisabled)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
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
        guard let product = storeService.annualProduct else { return "" }
        // Post-trial users no longer qualify for the free trial — Apple
        // enforces one per Apple ID. Showing "30 days free" to them would
        // be misleading (the system purchase sheet charges them immediately).
        if storeService.hadPremium {
            return "\(product.displayPrice)/year"
        }
        return "30 days free, then \(product.displayPrice)/year"
    }

    private var monthlySubtitle: String {
        guard let product = storeService.monthlyProduct else { return "" }
        if storeService.hadPremium {
            return "\(product.displayPrice)/month"
        }
        return "30 days free, then \(product.displayPrice)/month"
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
