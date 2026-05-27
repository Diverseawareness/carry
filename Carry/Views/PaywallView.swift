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
        case .startRound:          return "Starting rounds requires a subscription"
        case .createGroup:         return "Recurring Skins Groups require a subscription"
        case .scoreRound:          return "Scoring rounds requires a subscription"
        case .manageGroup:         return "Managing groups requires a subscription"
        case .allTimeLeaderboard:  return "All-time leaderboards require a subscription"
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

    /// Hero title — unified across audiences. Used to flip to "Trial Ended"
    /// for post-trial users, but the gate sheet (SubscriptionGateSheet)
    /// that funnels into this paywall now uses the same "Subscribe to
    /// Carry" copy, so the two surfaces match instead of disagreeing on
    /// framing mid-flow. Also was originally "Start Your Free Trial" for
    /// first-timers but Apple flagged that under 3.1.2(c) — trial-first
    /// framing made the trial more prominent than the billed amount. Trial
    /// mention now lives in the CTA summary (pre-trial only) + the bottom
    /// auto-renewal disclosure (required legal text).
    private var heroTitle: String {
        "Subscribe to Carry"
    }

    /// CTA button label — always "Subscribe" now. Previously "Try It Free"
    /// for first-timers, but Apple's 3.1.2(c) rejection flagged the most
    /// prominent screen element being trial-framed. "Subscribe" is neutral
    /// and works for both pre-trial and post-trial users — the trial copy
    /// lives on each price card ("30 days free, then $X/year") and in the
    /// bottom auto-renewal disclosure (required legal text).
    private var ctaButtonLabel: String {
        "Subscribe"
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
                    // users see the trial-ended framing instead of the
                    // first-time pitch. Contextual line appears only when
                    // a specific trigger was set. Glyph swapped from the
                    // old "premium-crown" to the Carry brand glyph —
                    // Carry doesn't market a "premium" tier any more.
                    VStack(spacing: 8) {
                        Image("carry-glyph")
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
                                    price: annualPrice,
                                    secondaryLine: annualSecondaryLine,
                                    detail: "Best value — full season coverage"
                                )
                            }
                            if storeService.monthlyProduct != nil {
                                planCard(
                                    type: .monthly,
                                    price: monthlyPrice,
                                    secondaryLine: monthlySecondaryLine,
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

                    // CTA button. Label is always "Subscribe" — the trial
                    // mention is intentionally absent from the most-tapped
                    // element on the screen, per the 3.1.2(c) fix. The
                    // billed amount + trial framing live (a) on each price
                    // card title/subtitle and (b) in the bottom auto-renew
                    // disclosure, so the redundant "$X/year or $Y/month ·
                    // Free 30-day trial" summary line we used to render
                    // above the CTA was dropped.
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
                        .padding(.top, 16)  // preserves the gap the now-removed summary line used to provide
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

    private func planCard(type: PlanType, price: String, secondaryLine: String, detail: String) -> some View {
        let isSelected = selectedPlan == type
        let planName = type == .annual ? "Annual" : "Monthly"

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlan = type
            }
        } label: {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        // PRICE is the visually dominant element per Apple
                        // 3.1.2(c). 24pt heavy primary, the largest text on
                        // the card. Plan name + trial copy are subordinate
                        // beneath it.
                        Text(price)
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(Color.textPrimary)
                        // Secondary line: plan name ("Annual" / "Monthly")
                        // for post-trial users, or trial copy ("30 days free,
                        // then $X/year") for first-timers. Smaller + lower
                        // contrast so the price reads first.
                        Text(secondaryLine)
                            .font(.system(size: 14))
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
        .accessibilityLabel("\(planName) plan, \(price), \(secondaryLine)")
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

    // MARK: - Plan card text (Apple 3.1.2(c) compliance)
    //
    // The billed price MUST be the visually dominant element. Plan name
    // ("Annual" / "Monthly") and trial copy are subordinate. We split the
    // old single "subtitle" property into two: `*Price` (the big bold price
    // string with period — the hero of the card) and `*SecondaryLine` (the
    // small grey label below — trial copy pre-trial, plan name post-trial).
    //
    // Post-trial users see the plan name only — they do NOT qualify for a
    // second free trial (Apple enforces one per Apple ID), so showing "30
    // days free" to them would be both false advertising AND a 3.1.2(c)
    // violation in its own right.

    private var annualPrice: String {
        guard let product = storeService.annualProduct else { return "" }
        return "\(product.displayPrice)/year"
    }

    private var monthlyPrice: String {
        guard let product = storeService.monthlyProduct else { return "" }
        return "\(product.displayPrice)/month"
    }

    private var annualSecondaryLine: String {
        guard let product = storeService.annualProduct else { return "" }
        return storeService.hadPremium
            ? "Annual"
            : "30 days free, then \(product.displayPrice)/year"
    }

    private var monthlySecondaryLine: String {
        guard let product = storeService.monthlyProduct else { return "" }
        return storeService.hadPremium
            ? "Monthly"
            : "30 days free, then \(product.displayPrice)/month"
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
