
import SwiftUI

#if DEBUG
struct DebugMenuView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appRouter: AppRouter
    @EnvironmentObject var storeService: StoreService
    @Environment(\.dismiss) var dismiss
    @State private var showPaywallPreview = false
    @State private var showShareCardPreview = false
    @State private var shareCardDarkMode = true

    var activeScenario: DebugScenario?
    var onNavigate: (DebugScenario) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZStack {
                Text("Debug Menu")
                    .font(.carry.labelBold)
                    .foregroundColor(Color.textPrimary)

                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.carry.bodyLGSemibold)
                        .foregroundColor(Color.textPrimary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 24) {
                    navigationSection
                    subscriptionSection
                    authSection
                    roundDataSection
                    playerSearchSection
                    inviteFlowSection
                    quickInfoSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color.bgSecondary)
    }

    // MARK: - Navigate To

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(DebugScenario.DebugSection.allCases, id: \.rawValue) { section in
                sectionHeader(section.rawValue)

                VStack(spacing: 0) {
                    ForEach(Array(section.scenarios.enumerated()), id: \.element.id) { index, scenario in
                        if index > 0 { divider }
                        scenarioRow(scenario)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(.white))
            }
        }
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("SUBSCRIPTION")

            VStack(spacing: 0) {
                toggleRow("isPremium", value: storeService.isPremium) {
                    storeService.isPremium.toggle()
                }
                divider
                actionRow("Show Paywall", icon: "crown") {
                    showPaywallPreview = true
                }
                divider
                actionRow("Show Share Card", icon: "square.and.arrow.up") {
                    showShareCardPreview = true
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        }
        .sheet(isPresented: $showPaywallPreview) {
            PaywallView()
        }
        .sheet(isPresented: $showShareCardPreview) {
            shareCardPreview
        }
    }

    // MARK: - Auth & User State

    private var authSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("AUTH & USER STATE")

            VStack(spacing: 0) {
                actionRow("Skip Auth (auto-login)", icon: "bolt.fill") {
                    authService.skipAuth()
                }
                divider
                actionRow("Sign Out", icon: "rectangle.portrait.and.arrow.right") {
                    Task { try? await authService.signOut() }
                }
                divider
                toggleRow("isAuthenticated", value: authService.isAuthenticated) {
                    authService.isAuthenticated.toggle()
                }
                divider
                toggleRow("isOnboarded", value: authService.isOnboarded) {
                    authService.isOnboarded.toggle()
                }
                divider
                toggleRow("isNewUser", value: authService.isNewUser) {
                    authService.isNewUser.toggle()
                }
                divider
                actionRow("Set Mock Profile", icon: "person.fill.checkmark") {
                    authService.currentUser = ProfileDTO(
                        id: UUID(),
                        firstName: "Daniel",
                        lastName: "Sigvardsson",
                        username: nil,
                        displayName: "Daniel",
                        initials: "DS",
                        color: "#D4A017",
                        avatar: "🏌️",
                        handicap: 6.5,
                        ghinNumber: "1234567",
                        homeClub: "Pine Valley Golf Club",
                        homeClubId: 12345,
                        email: "daniel@example.com",
                        createdAt: nil,
                        updatedAt: nil
                    )
                }
                divider
                actionRow("Clear Profile", icon: "person.slash") {
                    authService.currentUser = nil
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        }
    }

    // MARK: - Round & Game Data

    private var roundDataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("ROUND & GAME DATA")

            VStack(spacing: 0) {
                actionRow("Reset Demo Groups", icon: "arrow.counterclockwise") {
                    appRouter.debugResetGroups = true
                }
                divider
                actionRow("Clear All Groups", icon: "trash") {
                    appRouter.debugClearGroups = true
                }
                divider
                actionRow("Show Recurring Prompt", icon: "arrow.triangle.2.circlepath") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        appRouter.navigateToTab = "skinGames"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            appRouter.debugShowRecurringPrompt = true
                        }
                    }
                }
                divider
                actionRow("Show Quick Game Limit", icon: "exclamationmark.triangle") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        appRouter.navigateToTab = "skinGames"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            appRouter.debugShowQuickGameLimit = true
                        }
                    }
                }
                divider
                actionRow("Show Create Group Card", icon: "person.3.fill") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        appRouter.navigateToTab = "skinGames"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            appRouter.debugShowCreateGroupCard = true
                        }
                    }
                }
                divider
                actionRow("Show Invite Share Sheet", icon: "square.and.arrow.up") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        appRouter.navigateToTab = "skinGames"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            appRouter.debugShowInviteSheet = true
                        }
                    }
                }
                divider
                actionRow("Show Guest Claim Sheet", icon: "person.crop.circle.badge.questionmark") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        appRouter.navigateToTab = "home"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: .showDebugGuestClaim, object: nil)
                        }
                    }
                }
                divider
                actionRow(SyncQueue.shared.isOnline ? "Simulate Offline" : "Simulate Online", icon: "wifi.slash") {
                    SyncQueue.shared.isOnline.toggle()
                    dismiss()
                }
                divider
                actionRow("Simulate Deep Link Invite", icon: "link") {
                    appRouter.pendingGroupInvite = ParsedInvite(
                        groupId: nil,
                        groupName: "Debug Invite Group",
                        members: Array(Player.allPlayers.prefix(4))
                    )
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        }
    }

    // MARK: - Player Search & Username

    @State private var debugSearchQuery = ""
    @State private var debugSearchResults: [String] = []
    @State private var debugUsernameQuery = ""
    @State private var debugUsernameResult: String?

    private var playerSearchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("PLAYER SEARCH & USERNAME")

            VStack(spacing: 0) {
                // Search query input
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(Color.debugOrange)
                        .frame(width: 20)
                    TextField("Search players…", text: $debugSearchQuery)
                        .font(.system(size: 16))
                    if !debugSearchQuery.isEmpty {
                        Button {
                            debugSearchQuery = ""
                            debugSearchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color.textDisabled)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                divider

                actionRow("Search Online", icon: "antenna.radiowaves.left.and.right") {
                    let q = debugSearchQuery.isEmpty ? "dan" : debugSearchQuery
                    Task {
                        do {
                            let results = try await PlayerSearchService.shared.searchPlayers(query: q)
                            debugSearchResults = results.map { "\($0.displayName) @\($0.username ?? "–")" }
                        } catch {
                            debugSearchResults = ["Error: \(error.localizedDescription)"]
                        }
                    }
                }

                divider

                actionRow("Search Offline (Demo)", icon: "antenna.radiowaves.left.and.right.slash") {
                    let q = debugSearchQuery.isEmpty ? "dan" : debugSearchQuery
                    let results = PlayerSearchService.shared.searchPlayersOffline(query: q)
                    debugSearchResults = results.map { "\($0.displayName) @\($0.username ?? "–")" }
                }

                if !debugSearchResults.isEmpty {
                    divider

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(debugSearchResults, id: \.self) { entry in
                            Text(entry)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color.textTertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                divider

                // Username availability check
                HStack(spacing: 12) {
                    Image(systemName: "at")
                        .font(.system(size: 14))
                        .foregroundColor(Color.debugOrange)
                        .frame(width: 20)
                    TextField("Check username…", text: $debugUsernameQuery)
                        .font(.system(size: 16))
                        .autocapitalization(.none)
                    if let result = debugUsernameResult {
                        Text(result)
                            .font(.carry.micro)
                            .foregroundColor(result == "✓" ? Color(hexString: "#00D54B") : Color.systemRedColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                divider

                actionRow("Check Username", icon: "checkmark.shield") {
                    let u = debugUsernameQuery.isEmpty ? "daniels" : debugUsernameQuery
                    Task {
                        let available = await authService.checkUsernameAvailability(u)
                        debugUsernameResult = available ? "✓" : "✗"
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        }
    }

    // MARK: - Invite Flow

    @State private var debugInvitePhone = ""
    @State private var debugInviteLog: [String] = []

    private var inviteFlowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("INVITE FLOW")

            VStack(spacing: 0) {
                // Test phone input
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.debugOrange)
                        .frame(width: 20)
                    TextField("Test phone #", text: $debugInvitePhone)
                        .font(.system(size: 16))
                        .keyboardType(.phonePad)
                    if !debugInvitePhone.isEmpty {
                        Button {
                            debugInvitePhone = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color.textDisabled)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                divider

                actionRow("Send Test Invite", icon: "paperplane.fill") {
                    let phone = debugInvitePhone.isEmpty ? "5551234567" : debugInvitePhone
                    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                    debugInviteLog.insert("[\(timestamp)] SMS → \(phone)", at: 0)
                    print("[Carry Debug] Test invite SMS sent to \(phone)")
                }

                divider

                actionRow("Simulate Guest Accepts", icon: "person.fill.checkmark") {
                    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                    debugInviteLog.insert("[\(timestamp)] Guest accepted invite & signed up", at: 0)
                    print("[Carry Debug] Simulated guest accepting invite")
                }

                divider

                actionRow("Clear Invite Log", icon: "trash") {
                    debugInviteLog.removeAll()
                }

                if !debugInviteLog.isEmpty {
                    divider

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(debugInviteLog.prefix(5), id: \.self) { entry in
                            Text(entry)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color.textTertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        }
    }

    // MARK: - Quick Info

    private var quickInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("QUICK INFO")

            VStack(spacing: 0) {
                infoRow("Current User", value: authService.currentUser?.displayName ?? "nil")
                divider
                infoRow("Username", value: authService.currentUser?.username ?? "nil")
                divider
                infoRow("First Name", value: authService.currentUser?.firstName ?? "–")
                divider
                infoRow("Last Name", value: authService.currentUser?.lastName ?? "–")
                divider
                infoRow("isAuthenticated", value: authService.isAuthenticated ? "true" : "false")
                divider
                infoRow("isOnboarded", value: authService.isOnboarded ? "true" : "false")
                divider
                infoRow("Player Count", value: "\(Player.allPlayers.count)")
                divider
                infoRow("Demo Groups", value: "\(SavedGroup.demo.count)")
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        }
    }

    // MARK: - Row Components

    private func scenarioRow(_ scenario: DebugScenario) -> some View {
        let isActive = activeScenario == scenario
        return Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onNavigate(scenario)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: scenario.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? .white : Color.debugOrange)
                    .frame(width: 20)
                Text(scenario.label)
                    .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .white : Color.debugOrange)
                Spacer()
                if isActive {
                    Text("ACTIVE")
                        .font(.carry.microXS)
                        .foregroundColor(Color.debugOrange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.9)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(isActive ? Color.debugOrange : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func actionRow(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color.debugOrange)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(Color.debugOrange)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ label: String, value: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(value ? Color(hexString: "#00D54B") : Color.textDisabled)
                    .frame(width: 8, height: 8)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(Color.debugOrange)
                Spacer()
                Text(value ? "true" : "false")
                    .font(.carry.bodySM)
                    .monospacedDigit()
                    .foregroundColor(value ? Color(hexString: "#00D54B") : Color.textDisabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Color.textTertiary)
            Spacer()
            Text(value)
                .font(.carry.bodySM)
                .foregroundColor(Color.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.carry.captionSemibold)
            .foregroundColor(Color.textTertiary)
            .tracking(CarryTracking.wide)
            .padding(.leading, 4)
            .padding(.top, 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.bgPrimary)
            .frame(height: 1)
            .padding(.leading, 48)
    }

    // MARK: - Share Card Preview

    private var shareCardPreview: some View {
        let sampleData = ShareCardData(
            courseName: "Ruby Hill Golf Club",
            date: Date(),
            teeName: "Combos",
            handicapPct: 70,
            entries: [
                ShareCardEntry(name: "Daniel Sigvardsson", initials: "DS", color: "#D4A017", skinsWon: 5, moneyAmount: 45),
                ShareCardEntry(name: "Tyson Briner", initials: "TB", color: "#E67E22", skinsWon: 3, moneyAmount: 15),
                ShareCardEntry(name: "Garret Edwards", initials: "GE", color: "#4A90D9", skinsWon: 1, moneyAmount: -10),
                ShareCardEntry(name: "Jon Jones", initials: "JJ", color: "#2ECC71", skinsWon: 0, moneyAmount: -25),
            ],
            potTotal: 100,
            buyIn: 25
        )

        let theme: ShareCardTheme = shareCardDarkMode ? .dark : .light

        return ScrollView {
            VStack(spacing: 20) {
                Text("Share Card Preview")
                    .font(.carry.labelBold)
                    .padding(.top, 20)

                // Theme toggle
                Picker("Theme", selection: $shareCardDarkMode) {
                    Text("Dark").tag(true)
                    Text("Light").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)

                ResultsShareCard(data: sampleData, theme: theme)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(shareCardDarkMode ? 0.3 : 0.15), radius: 20, y: 10)
                    .padding(.horizontal, 12)
                    .animation(.easeInOut(duration: 0.2), value: shareCardDarkMode)

                if let image = ShareCardRenderer.render(data: sampleData, theme: theme) {
                    Text("Rendered: \(Int(image.size.width))x\(Int(image.size.height))pt")
                        .font(.carry.caption)
                        .foregroundColor(Color.textTertiary)
                }
            }
            .padding(.bottom, 40)
        }
        .background(shareCardDarkMode ? Color.bgSecondary : Color(hexString: "#E8E8ED"))
    }
}
#endif
