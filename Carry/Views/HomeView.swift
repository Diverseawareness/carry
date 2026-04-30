import SwiftUI

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

// MARK: - Home Round Model

enum HomeRoundStatus: String {
    case active, invited, concluded, completed, groupInvite
}

struct HomeRound: Identifiable {
    let id: UUID
    let groupName: String
    let courseName: String     // e.g. "Torrey Pines South"
    let players: [Player]
    let status: HomeRoundStatus
    let currentHole: Int       // 0 for not started
    let totalHoles: Int        // 9 or 18
    let buyIn: Int
    let skinsWon: Int          // total skins won so far
    let totalSkins: Int        // total skins available
    let yourSkins: Int         // current user's skins won
    let invitedBy: String?     // name of person who invited (for .invited)
    let creatorId: Int         // player ID of round creator
    var scorerPlayerId: Int? = nil  // player ID of designated scorer (nil = creator scores)
    var teeBox: TeeBox? = nil       // tee box for handicap calculations
    var supabaseGroupId: UUID? = nil // group ID for Supabase linking
    var roundsPlayed: Int = 0  // total rounds played in this group
    var pendingGroups: Int = 0 // groups with pending results
    var totalGroups: Int = 1   // total groups in the round
    var completedGroups: Int = 0  // groups that finished all 18 holes

    var yourWinnings: Int { yourSkins * skinValue }
    let startedAt: Date?
    let completedAt: Date?
    var scheduledDate: Date? = nil  // upcoming tee time (for invites / upcoming display)
    var concludedAt: Date? = nil    // when all groups finished (concluded state)
    var viewedFinalResults: Bool = false  // user has seen final results sheet
    var playerWinnings: [Int: Int] = [:]  // [playerID: dollars won]
    var playerWonHoles: [Int: [Int]] = [:]  // [playerID: hole numbers won]
    var pendingHoleLeaders: [PendingHoleLeader] = []  // pending holes with current leaders
    var userGroupComplete: Bool = false  // true when the current user's group has all holes scored
    var scoringMode: ScoringMode = .single  // .single or .everyone
    var skinRules: SkinRules = .default  // actual round settings (net/gross, carries, handicap%)
    var winningsDisplay: String = "gross"  // "gross" (default) or "net" — how winnings show in UI
    var isQuickGame: Bool = false

    struct PendingHoleLeader: Identifiable {
        let id: Int  // hole number
        let holeNum: Int
        let leader: Player?  // current leader (nil = no scores yet)
        let score: Int  // leader's net score
        let scored: Int  // players scored so far
        let total: Int  // total players
    }

    /// Players sorted by winnings (leader first), then by name for ties
    var sortedPlayers: [Player] {
        players.sorted { a, b in
            let aWin = playerWinnings[a.id] ?? 0
            let bWin = playerWinnings[b.id] ?? 0
            if aWin != bWin { return aWin > bWin }
            return a.name < b.name
        }
    }

    var skinValue: Int {
        guard totalSkins > 0 else { return 0 }
        // Completed rounds: divide by skins actually won (true per-skin value).
        // Active/invited: divide by totalSkins (base per-hole estimate).
        let denom = ((status == .completed || status == .concluded) && skinsWon > 0) ? skinsWon : totalSkins
        return Int((Double(potTotal) / Double(denom)).rounded())
    }

    var activePlayerCount: Int = 0  // players who actually scored (set by GroupService)
    var potTotal: Int { buyIn * (activePlayerCount > 0 ? activePlayerCount : players.count) }

    /// The round is finished — either all groups scored every hole OR the
    /// host force-ended early (status flips to `.concluded` / `.completed`).
    /// Previously this only counted 18-hole completions, so a force-ended
    /// round at hole 5 still rendered as "live scoring" on the home card
    /// and the results sheet said "Pending Results." Respecting server
    /// status here fixes both.
    var isGameDone: Bool {
        if status == .concluded || status == .completed { return true }
        return completedGroups == totalGroups && totalGroups > 0
    }

    /// At least one group finished all 18, but not all
    var hasPendingResults: Bool {
        completedGroups >= 1 && !isGameDone
    }

    var holeLabel: String {
        if currentHole == 0 { return "Not started" }
        if isGameDone || status == .completed || status == .concluded { return "Final" }
        return "Hole \(currentHole)"
    }

    var timeLabel: String {
        if let completed = completedAt {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            return fmt.localizedString(for: completed, relativeTo: Date())
        }
        if let started = startedAt {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            return fmt.localizedString(for: started, relativeTo: Date())
        }
        return ""
    }

    /// Bold header for active card: "11:21 AM" or group name as fallback
    var teeTimeHeader: String {
        guard let date = scheduledDate else { return groupName }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        return timeFormatter.string(from: date)
    }

    /// Human-readable scheduled date, e.g. "Sat, Mar 14 · 8:24 AM" or "Today · 8:24 AM"
    var scheduledLabel: String? {
        guard let date = scheduledDate else { return nil }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let time = timeFormatter.string(from: date)
        if Calendar.current.isDateInToday(date) {
            return "Today · \(time)"
        }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE, MMM d"
        return "\(dayFormatter.string(from: date)) · \(time)"
    }

    // MARK: Demo Data

    #if DEBUG
    // MARK: - State 1: Start Round (not started, currentHole == 0)
    static let demoStartRound: HomeRound = HomeRound(
        id: UUID(),
        groupName: "The Friday Skins",
        courseName: "Torrey Pines South",
        players: Player.allPlayers,
        status: .active,
        currentHole: 0,
        totalHoles: 18,
        buyIn: 50,
        skinsWon: 0,
        totalSkins: 18,
        yourSkins: 0,
        invitedBy: nil,
        creatorId: 1,
        pendingGroups: 4,
        totalGroups: 4,
        completedGroups: 0,
        startedAt: Calendar.current.date(byAdding: .hour, value: -1, to: Date()),
        completedAt: nil,
        scheduledDate: Calendar.current.date(byAdding: .hour, value: -1, to: Date()),
        playerWinnings: [:],
        playerWonHoles: [:]
    )

    // MARK: - State 2: LIVE Scorecard (all groups live, none completed)
    static let demoLiveScoreCard: HomeRound = HomeRound(
        id: UUID(),
        groupName: "The Friday Skins",
        courseName: "Torrey Pines South",
        players: Player.allPlayers,
        status: .active,
        currentHole: 3,
        totalHoles: 18,
        buyIn: 50,
        skinsWon: 2,
        totalSkins: 18,
        yourSkins: 1,
        invitedBy: nil,
        creatorId: 1,
        pendingGroups: 4,
        totalGroups: 4,
        completedGroups: 0,
        startedAt: Calendar.current.date(byAdding: .hour, value: -1, to: Date()),
        completedAt: nil,
        scheduledDate: Calendar.current.date(byAdding: .hour, value: -1, to: Date()),
        playerWinnings: [1: 45, 3: 22],  // Cameron: $45, Adi: $22
        playerWonHoles: [1: [1], 3: [3]]
    )

    // MARK: - State 3: Pending Results (1+ groups completed all 18)
    static let demoPendingResults: HomeRound = HomeRound(
        id: UUID(),
        groupName: "The Friday Skins",
        courseName: "Torrey Pines South",
        players: Player.allPlayers,
        status: .active,
        currentHole: 7,
        totalHoles: 18,
        buyIn: 50,
        skinsWon: 5,
        totalSkins: 18,
        yourSkins: 2,
        invitedBy: nil,
        creatorId: 1,
        pendingGroups: 2,
        totalGroups: 4,
        completedGroups: 2,
        startedAt: Calendar.current.date(byAdding: .hour, value: -2, to: Date()),
        completedAt: nil,
        scheduledDate: Calendar.current.date(byAdding: .hour, value: -2, to: Date()),
        playerWinnings: [1: 66, 3: 66],  // Cameron: $66, Adi: $66
        playerWonHoles: [1: [1, 5], 3: [2, 3, 7]],
        pendingHoleLeaders: [
            HomeRound.PendingHoleLeader(id: 4, holeNum: 4, leader: Player.allPlayers[3], score: 3, scored: 8, total: 12),
            HomeRound.PendingHoleLeader(id: 6, holeNum: 6, leader: Player.allPlayers[1], score: 3, scored: 8, total: 12),
            HomeRound.PendingHoleLeader(id: 8, holeNum: 8, leader: nil, score: 0, scored: 0, total: 12),
            HomeRound.PendingHoleLeader(id: 9, holeNum: 9, leader: nil, score: 0, scored: 0, total: 12),
            HomeRound.PendingHoleLeader(id: 10, holeNum: 10, leader: nil, score: 0, scored: 0, total: 12),
            HomeRound.PendingHoleLeader(id: 11, holeNum: 11, leader: nil, score: 0, scored: 0, total: 12),
            HomeRound.PendingHoleLeader(id: 12, holeNum: 12, leader: nil, score: 0, scored: 0, total: 12),
            HomeRound.PendingHoleLeader(id: 13, holeNum: 13, leader: nil, score: 0, scored: 0, total: 12),
            HomeRound.PendingHoleLeader(id: 14, holeNum: 14, leader: nil, score: 0, scored: 0, total: 12),
            HomeRound.PendingHoleLeader(id: 15, holeNum: 15, leader: nil, score: 0, scored: 0, total: 12),
            HomeRound.PendingHoleLeader(id: 16, holeNum: 16, leader: nil, score: 0, scored: 0, total: 12),
            HomeRound.PendingHoleLeader(id: 17, holeNum: 17, leader: nil, score: 0, scored: 0, total: 12),
            HomeRound.PendingHoleLeader(id: 18, holeNum: 18, leader: nil, score: 0, scored: 0, total: 12),
        ]
    )

    // MARK: - State 4: Game Done (all groups completed all 18)
    static let demoGameDone: HomeRound = HomeRound(
        id: UUID(),
        groupName: "The Friday Skins",
        courseName: "Torrey Pines South",
        players: Player.allPlayers,
        status: .active,
        currentHole: 18,
        totalHoles: 18,
        buyIn: 50,
        skinsWon: 12,
        totalSkins: 18,
        yourSkins: 3,
        invitedBy: nil,
        creatorId: 1,
        pendingGroups: 0,
        totalGroups: 4,
        completedGroups: 4,
        startedAt: Calendar.current.date(byAdding: .hour, value: -4, to: Date()),
        completedAt: nil,
        scheduledDate: Calendar.current.date(byAdding: .hour, value: -4, to: Date()),
        concludedAt: Date(),
        playerWinnings: [1: 150, 3: 100, 2: 100, 6: 50, 5: 50, 9: 50, 10: 50, 8: 50],
        playerWonHoles: [1: [3, 7, 11], 3: [1, 5], 2: [9, 14], 6: [2], 5: [8], 9: [16], 10: [4], 8: [13]]
    )

    // Legacy arrays — kept for backward compatibility
    static let demoActive: [HomeRound] = [
        demoStartRound,
        demoPendingResults,
    ]

    static let demoConcluded: [HomeRound] = [
        demoGameDone,
    ]

    /// All 4 active card states for debug scenario
    static let demoAllCardStates: [HomeRound] = [
        demoStartRound,
        demoLiveScoreCard,
        demoPendingResults,
        demoGameDone,
    ]

    static let demoInvited: [HomeRound] = [
        HomeRound(
            id: UUID(),
            groupName: "Weekend Warriors",
            courseName: "Balboa Park Golf Course",
            players: Array(Player.allPlayers.prefix(4)),
            status: .invited,
            currentHole: 0,
            totalHoles: 18,
            buyIn: 100,
            skinsWon: 0,
            totalSkins: 18,
            yourSkins: 0,
            invitedBy: "Garret",
            creatorId: 2,
            startedAt: nil,
            completedAt: nil,
            scheduledDate: Calendar.current.date(byAdding: .day, value: 3, to: Date())
        ),
    ]

    static let demoRecent: [HomeRound] = [
        HomeRound(
            id: UUID(),
            groupName: "The Friday Skins",
            courseName: "Ruby Hill",
            players: Player.allPlayers,          // 12 players × $50 = $600
            status: .completed,
            currentHole: 18,
            totalHoles: 18,
            buyIn: 50,
            skinsWon: 8,
            totalSkins: 18,
            yourSkins: 2,
            invitedBy: nil,
            creatorId: 1,
            roundsPlayed: 4,
            startedAt: Calendar.current.date(byAdding: .hour, value: -5, to: Date()),
            completedAt: Calendar.current.date(byAdding: .hour, value: -1, to: Date()),
            // 8 skins won: $75/skin. Daniel 2, Adi 2, Garret 1, Tyson 1, Keith 1, Ronnie 1
            playerWinnings: [1: 150, 3: 150, 2: 75, 6: 75, 5: 75, 9: 75],
            playerWonHoles: [1: [3, 11], 3: [1, 7], 2: [5], 6: [9], 5: [14], 9: [16]]
        ),
        HomeRound(
            id: UUID(),
            groupName: "The Friday Skins",
            courseName: "Torrey Pines South",
            players: Player.allPlayers,          // 12 players × $50 = $600
            status: .completed,
            currentHole: 18,
            totalHoles: 18,
            buyIn: 50,
            skinsWon: 14,
            totalSkins: 18,
            yourSkins: 3,
            invitedBy: nil,
            creatorId: 1,
            roundsPlayed: 4,
            startedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date()),
            completedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date()),
            // 14 skins won: ~$43/skin. Daniel 3, Garret 3, Adi 2, Tyson 2, Keith 2, AJ 1, Cameron 1
            playerWinnings: [1: 129, 2: 129, 3: 86, 6: 86, 5: 86, 8: 43, 10: 43]
        ),
        HomeRound(
            id: UUID(),
            groupName: "Thursday Boys",
            courseName: "Riverwalk Golf Club",
            players: Array(Player.allPlayers.suffix(4)),
            status: .completed,
            currentHole: 18,
            totalHoles: 18,
            buyIn: 25,
            skinsWon: 12,
            totalSkins: 18,
            yourSkins: 0,
            invitedBy: nil,
            creatorId: 9,
            roundsPlayed: 2,
            startedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date()),
            completedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date())
        ),
    ]
    #endif
}

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var storeService: StoreService
    @EnvironmentObject var appRouter: AppRouter
    @Binding var selectedTab: MainTabView.Tab
    @Binding var skinGameGroups: [SavedGroup]
    var isLoadingGroups: Bool = false
    @Binding var pendingActiveGroupId: UUID?
    @State private var showPaywall = false
    @State private var showCreateGroup = false
    @State private var showQRScanner = false
    /// When the user arrives from `invite.html` → App Store download → install,
    /// the invite URL is copied to their clipboard by the web page (see
    /// `site/invite.html`). Post-onboarding we surface a one-tap banner on
    /// Home so they can complete the join without rescanning the QR.
    /// The `hasURLs` check is privacy-preserving — it does NOT trigger the
    /// iOS paste banner. That prompt only fires when the user taps the
    /// banner, at which point we read the URL and route through the same
    /// `handleScannedInvite` path as the QR scanner.
    @State private var clipboardInviteAvailable = false
    @State private var didDismissClipboardInvite = false
    /// System-wide `UIPasteboard.changeCount` value at the moment the user
    /// last acknowledged the clipboard invite alert (either tapped Join or
    /// Cancel). Stored via `@AppStorage` so it persists across app launches
    /// and across HomeView re-creations (SwiftUI destroys + rebuilds the
    /// view on tab switches, which would otherwise reset session flags and
    /// re-fire the alert for the same clipboard content).
    @AppStorage("clipboardInviteAckdChangeCount") private var clipboardInviteAckdChangeCount: Int = -1
    @State private var invitedRounds: [HomeRound] = []
    @State private var pendingInvites: [InviteDTO] = []  // raw Supabase invites
    @State private var selectedRound: HomeRound?
    @State private var leaderboardRound: HomeRound?
    @State private var activeCardPulse = false
    @State private var resultsRound: HomeRound?
    @State private var roundToLeave: HomeRound?
    @State private var roundToDelete: HomeRound?
    @State private var loadingQuipIndex: Int = 0
    @State private var showGuestClaimSheet = false
    @State private var guestClaimProfiles: [ProfileDTO] = []
    @State private var guestClaimId: UUID? = nil  // triggers .sheet(item:)
    @State private var pendingClaimRound: HomeRound? = nil
    @State private var acceptingInviteId: UUID? = nil  // round ID currently being accepted
    /// Invite the user was trying to accept when the paywall forced them to
    /// subscribe first. Auto-accepted in the onChange(of: isPremium) handler
    /// once the trial/subscription activates, so tapping Join once is enough.
    @State private var pendingInviteAfterPaywall: HomeRound? = nil

    private let roundService = RoundService()
    @State private var homePoller: Timer?

    private let loadingQuips = [
        "Adjusting the visor...",
        "Fixing that slice...",
        "Settling last week's bets...",
        "Finding the cart girl...",
        "Blaming the wind...",
        "Foot wedging out of the rough...",
        "One more on the range...",
        "Marking that gimme...",
    ]
    @State private var quipTimer: Timer?
    private var currentUserId: Int { authService.currentPlayerId }

    private func startQuipRotation() {
        quipTimer?.invalidate()
        quipTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                loadingQuipIndex += 1
            }
        }
    }

    /// Active rounds — includes both `active` and `concluded` rounds.
    /// Concluded means all groups finished but the user hasn't reviewed/saved results yet,
    /// so they stay pinned at the top until explicitly dismissed via "Save Round Results".
    private var activeRounds: [HomeRound] {
        skinGameGroups.flatMap { group -> [HomeRound] in
            var out: [HomeRound] = []
            if let active = group.activeRound { out.append(active) }
            if let concluded = group.concludedRound { out.append(concluded) }
            return out
        }
    }

    /// Recent rounds derived from all groups' round history (NOT concluded — those stay
    /// in the Active section until the user saves results).
    private var recentRounds: [HomeRound] {
        let history: [HomeRound] = skinGameGroups.flatMap { group in
            group.roundHistory.map { round in
                var r = round
                r.roundsPlayed = group.roundHistory.count
                return r
            }
        }
        var seen = Set<UUID>()
        let deduped = history.filter { seen.insert($0.id).inserted }
        return deduped.sorted { ($0.completedAt ?? $0.concludedAt ?? .distantPast) > ($1.completedAt ?? $1.concludedAt ?? .distantPast) }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 24) {
            GolfBallLoader(size: 60)
            Text("\"\(loadingQuips[loadingQuipIndex % loadingQuips.count])\"")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color(hexString: "#4A4A4A"))
                .id(loadingQuipIndex)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.9)),
                    removal: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.9))
                ))
                .onAppear {
                    loadingQuipIndex = Int.random(in: 0..<loadingQuips.count)
                    startQuipRotation()
                }
                .onDisappear {
                    quipTimer?.invalidate()
                    quipTimer = nil
                }
        }
    }

    var body: some View {
        ZStack {
            Color.bgSecondary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(greeting)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color.pureBlack)
                        .transaction { $0.animation = nil }
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        showQRScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                            .foregroundColor(Color.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Scan invite QR code")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 0) {
                    // MARK: New User CTA
                    if skinGameGroups.isEmpty && !isLoadingGroups {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2.fill")
                                .font(.carry.displaySM)
                                .foregroundColor(Color.textDisabled)

                            Text("No Skin Games Yet")
                                .font(.carry.bodyLG)
                                .foregroundColor(Color.textTertiary)

                            Text("Create a skin game to track skins with your crew.")
                                .font(.carry.captionLG)
                                .foregroundColor(Color.textDisabled)
                                .multilineTextAlignment(.center)

                            Button {
                                selectedTab = .skinGames
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    NotificationCenter.default.post(name: .showNewGamePicker, object: nil)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("New Skins Game")
                                        .font(.carry.bodySMBold)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(Color.pureBlack)
                                )
                            }
                            .padding(.top, 8)
                        }
                        .padding(.vertical, 60)
                    }

                    // MARK: Active Rounds
                    sectionHeader("Active Rounds", count: activeRounds.count)

                    if activeRounds.isEmpty {
                        emptyCard("No Active Rounds", icon: "figure.golf")
                    } else {
                        ForEach(activeRounds) { round in
                            activeRoundCard(round)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                    }

                    // MARK: Pending Invites
                    sectionHeader("Invites", count: invitedRounds.count)
                        .padding(.top, 16)

                    if invitedRounds.isEmpty {
                        emptyCard("No pending invites", icon: "envelope")
                    } else {
                        ForEach(invitedRounds) { round in
                            inviteCard(round)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                    }

                    // MARK: Recent Rounds
                    sectionHeader("Recent Games", count: recentRounds.count)
                        .padding(.top, 16)

                    if recentRounds.isEmpty {
                        emptyCard("No Recent Games", icon: "clock")
                    } else {
                        let visibleRounds = storeService.isPremium
                            ? recentRounds
                            : Array(recentRounds.prefix(1))
                        ForEach(visibleRounds) { round in
                            swipeToLeaveWrapper(round: round) {
                                recentRoundCard(round)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                        if !storeService.isPremium && recentRounds.count > 1 {
                            Button {
                                showPaywall = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image("premium-crown")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 14, height: 14)
                                    Text("View full history")
                                        .font(.carry.bodySMSemibold)
                                        .foregroundColor(Color.textPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(RoundedRectangle(cornerRadius: 13).fill(.white))
                                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.dividerLight, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                    }

                    Spacer().frame(height: 80)
                }
            }
            .refreshable {
                if authService.isAuthenticated, let userId = authService.currentUser?.id {
                    let groupService = GroupService()
                    if let refreshed = try? await groupService.loadGroups(userId: userId) {
                        skinGameGroups = refreshed
                    }
                } else {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
            } // end outer VStack

            // Top fade gradient under status bar / dynamic island
            VStack {
                LinearGradient(
                    colors: [Color.bgSecondary, Color.bgSecondary.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 50)
                .allowsHitTesting(false)
                Spacer()
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .overlay {
            if isLoadingGroups && isEmptyState {
                ZStack {
                    Color.bgSecondary.ignoresSafeArea()
                    loadingOverlay
                }
            }
        }
        .overlay {
            if let round = selectedRound {
                RoundCoordinatorView(
                    initialMembers: round.players,
                    groupName: round.groupName,
                    currentUserId: authService.currentPlayerId,
                    startInActiveMode: round.status == .active || round.status == .concluded,
                    initialRoundConfig: Self.buildRoundConfig(from: round),
                    roundHistory: skinGameGroups.first(where: { $0.activeRound?.id == round.id || $0.concludedRound?.id == round.id })?.roundHistory ?? [],
                    onExit: {
                        // Don't mutate local state on exit — let the async refresh below be
                        // the single source of truth. Active rounds (incl. multi-group pending
                        // state) should stay visible until they actually transition state in
                        // Supabase. Concluded rounds stay pinned until user taps Save.
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                            selectedRound = nil
                            selectedTab = .skinGames
                        }
                        // Refresh groups to get updated data from Supabase
                        if authService.isAuthenticated, let userId = authService.currentUser?.id {
                            Task {
                                if let refreshed = try? await GroupService().loadGroups(userId: userId) {
                                    skinGameGroups = refreshed
                                }
                            }
                        }
                    },
                    onLeaveGroup: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                            selectedRound = nil
                            skinGameGroups.removeAll { $0.activeRound?.id == round.id || $0.concludedRound?.id == round.id }
                        }
                    },
                    onDeleteGroup: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                            selectedRound = nil
                            skinGameGroups.removeAll { $0.activeRound?.id == round.id || $0.concludedRound?.id == round.id }
                        }
                    },
                    isViewer: (round.status == .active || round.status == .concluded) && authService.currentPlayerId != (round.scorerPlayerId ?? round.creatorId) && authService.currentPlayerId != round.creatorId,
                    isQuickGame: skinGameGroups.first(where: { $0.activeRound?.id == round.id || $0.concludedRound?.id == round.id })?.isQuickGame ?? false,
                    onDeclineGroup: {
                        if let idx = skinGameGroups.firstIndex(where: { $0.activeRound?.id == round.id || $0.concludedRound?.id == round.id }) {
                            skinGameGroups[idx].archiveConcludedRound()
                        }
                    }
                )
                .ignoresSafeArea()
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: selectedRound?.id)
        // Hide the parent tab bar whenever a round is fullscreen-presented.
        // Re-publishes on every body recomputation, so unmounting the view
        // (e.g. switching tabs) automatically clears the contribution.
        .preference(key: TabBarHiddenKey.self, value: selectedRound != nil)
        .onChange(of: storeService.isPremium) { _, newValue in
            // User completed the forced paywall (trial started or subscribed).
            // Auto-accept the invite that triggered the paywall so they don't
            // have to tap Join a second time.
            if newValue, let pending = pendingInviteAfterPaywall {
                pendingInviteAfterPaywall = nil
                acceptInvite(pending)
            }
        }
        .sheet(item: $leaderboardRound) { round in
            let groupHistory = skinGameGroups.first(where: { $0.name == round.groupName })?.roundHistory ?? []
            LeaderboardSheet(round: round, groupRoundHistory: groupHistory)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(item: $resultsRound) { round in
            // Only the creator can finalize the round (flip active/concluded
            // → completed). Members see the results but have no finalize
            // button — that's the host's call. `canSaveResults` returns false
            // when `onSaveResults` is nil, so the button stays hidden for
            // non-creators.
            let isRoundCreator = currentUserId == round.creatorId
            ResultsSheet(
                round: round,
                currentUserId: currentUserId,
                onSaveResults: isRoundCreator ? {
                    // Mark the round as completed so it moves from active → recent
                    Task {
                        try? await RoundService().updateRoundStatus(roundId: round.id, status: "completed")
                        if let userId = authService.currentUser?.id,
                           let refreshed = try? await GroupService().loadGroups(userId: userId) {
                            await MainActor.run {
                                skinGameGroups = refreshed
                            }
                        }
                    }
                    resultsRound = nil
                } : nil
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showGuestClaimSheet) {
            GuestClaimSheet(
                profiles: guestClaimProfiles,
                groupName: pendingClaimRound?.groupName ?? "Skins Group",
                onClaim: { guestId in claimGuestAndJoin(guestId: guestId) },
                onSkip: { skipClaimAndJoin() }
            )
        }
        .sheet(item: $guestClaimId) { _ in
            GuestClaimSheet(
                profiles: [
                    ProfileDTO(id: UUID(), firstName: "Tyson", lastName: "Briner", username: nil, displayName: "Tyson Briner", initials: "TB", color: "#E67E22", avatar: "", handicap: 0.9, ghinNumber: nil, homeClub: nil, homeClubId: nil, avatarUrl: nil, email: nil, isClubMember: nil, isGuest: true, createdBy: nil, createdAt: nil, updatedAt: nil),
                    ProfileDTO(id: UUID(), firstName: "Garret", lastName: "Edwards", username: nil, displayName: "Garret Edwards", initials: "GE", color: "#4A90D9", avatar: "", handicap: 13.7, ghinNumber: nil, homeClub: nil, homeClubId: nil, avatarUrl: nil, email: nil, isClubMember: nil, isGuest: true, createdBy: nil, createdAt: nil, updatedAt: nil),
                    ProfileDTO(id: UUID(), firstName: "Jon", lastName: "Jones", username: nil, displayName: "Jon Jones", initials: "JJ", color: "#2ECC71", avatar: "", handicap: 8.2, ghinNumber: nil, homeClub: nil, homeClubId: nil, avatarUrl: nil, email: nil, isClubMember: nil, isGuest: true, createdBy: nil, createdAt: nil, updatedAt: nil),
                    ProfileDTO(id: UUID(), firstName: "Keith", lastName: "Baker", username: nil, displayName: "Keith Baker", initials: "KB", color: "#9B59B6", avatar: "", handicap: 6.2, ghinNumber: nil, homeClub: nil, homeClubId: nil, avatarUrl: nil, email: nil, isClubMember: nil, isGuest: true, createdBy: nil, createdAt: nil, updatedAt: nil),
                ],
                groupName: "Debug Group",
                onClaim: { _ in guestClaimId = nil },
                onSkip: { guestClaimId = nil }
            )
        }
        .sheet(isPresented: $showCreateGroup) {
            CreateGroupSheet { newGroup in
                skinGameGroups.insert(newGroup, at: 0)
                showCreateGroup = false
                selectedTab = .skinGames
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.white)
        }
        .fullScreenCover(isPresented: $showQRScanner) {
            QRScannerView { payload in
                handleScannedInvite(payload)
            }
        }
        // Post-install bridge for scan-via-iPhone-Camera → install → open
        // Carry. Fires once per session when the clipboard holds a URL
        // (hasURLs is privacy-preserving — no paste banner here). Tapping
        // Join triggers the "Allow Paste" prompt and routes the URL
        // through the same `handleScannedInvite` path as a QR scan,
        // landing the user directly inside the group.
        .alert("Open your invite?", isPresented: Binding(
            get: { clipboardInviteAvailable && !didDismissClipboardInvite },
            set: { if !$0 { markClipboardInviteAcknowledged() } }
        )) {
            Button("Open") { consumeClipboardInvite() }
            Button("Not Now", role: .cancel) {
                markClipboardInviteAcknowledged()
            }
        } message: {
            Text("Tap Open and choose Allow Paste when iOS asks — we'll take you straight to your group.")
        }
        .alert("Leave Group?", isPresented: Binding(
            get: { roundToLeave != nil },
            set: { if !$0 { roundToLeave = nil } }
        )) {
            Button("Cancel", role: .cancel) { roundToLeave = nil }
            Button("Leave", role: .destructive) {
                if let round = roundToLeave {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        removeRound(round)
                    }
                    roundToLeave = nil
                }
            }
        } message: {
            if let round = roundToLeave {
                Text("You'll be removed from \(round.groupName). This can't be undone.")
            }
        }
        .onAppear {
            // In dev mode with groups, seed demo invites for visual testing
            #if DEBUG
            if authService.currentUser == nil && !skinGameGroups.isEmpty && invitedRounds.isEmpty {
                invitedRounds = HomeRound.demoInvited
            }
            #endif
            // Fetch real invites from Supabase when authenticated
            if authService.isAuthenticated, let userId = authService.currentUser?.id {
                Task { await loadInvites(userId: userId) }
            }
            startHomePoller()
            // Post-install bridge: did invite.html copy a URL to the
            // clipboard that we can surface as a one-tap banner?
            checkClipboardForInvite()
        }
        #if DEBUG
        .onChange(of: appRouter.debugSimulateClipboardInvite) { _, shouldSimulate in
            guard shouldSimulate else { return }
            appRouter.debugSimulateClipboardInvite = false
            // Reset both the session dismissal flag AND the persisted
            // `changeCount` acknowledgement so the debug action can always
            // re-trigger the alert even if we previously dismissed it for
            // the same clipboard content.
            didDismissClipboardInvite = false
            clipboardInviteAckdChangeCount = -1
            checkClipboardForInvite()
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .showDebugGuestClaim)) { _ in
            let mockProfiles = [
                ProfileDTO(id: UUID(), firstName: "Tyson", lastName: "Briner", username: nil, displayName: "Tyson Briner", initials: "TB", color: "#E67E22", avatar: "", handicap: 0.9, ghinNumber: nil, homeClub: nil, homeClubId: nil, avatarUrl: nil, email: nil, isClubMember: nil, isGuest: true, createdBy: nil, createdAt: nil, updatedAt: nil),
                ProfileDTO(id: UUID(), firstName: "Garret", lastName: "Edwards", username: nil, displayName: "Garret Edwards", initials: "GE", color: "#4A90D9", avatar: "", handicap: 13.7, ghinNumber: nil, homeClub: nil, homeClubId: nil, avatarUrl: nil, email: nil, isClubMember: nil, isGuest: true, createdBy: nil, createdAt: nil, updatedAt: nil),
                ProfileDTO(id: UUID(), firstName: "Jon", lastName: "Jones", username: nil, displayName: "Jon Jones", initials: "JJ", color: "#2ECC71", avatar: "", handicap: 8.2, ghinNumber: nil, homeClub: nil, homeClubId: nil, avatarUrl: nil, email: nil, isClubMember: nil, isGuest: true, createdBy: nil, createdAt: nil, updatedAt: nil),
                ProfileDTO(id: UUID(), firstName: "Keith", lastName: "Baker", username: nil, displayName: "Keith Baker", initials: "KB", color: "#9B59B6", avatar: "", handicap: 6.2, ghinNumber: nil, homeClub: nil, homeClubId: nil, avatarUrl: nil, email: nil, isClubMember: nil, isGuest: true, createdBy: nil, createdAt: nil, updatedAt: nil),
            ]
            guestClaimProfiles = mockProfiles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guestClaimId = UUID()  // triggers item-based sheet with fresh data
            }
        }
        .onDisappear {
            stopHomePoller()
        }
        .alert("Delete Skins Game?", isPresented: Binding(
            get: { roundToDelete != nil },
            set: { if !$0 { roundToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { roundToDelete = nil }
            Button("Delete", role: .destructive) {
                if let round = roundToDelete {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        removeRound(round)
                    }
                    roundToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete this Skins Game, including all scores, leaderboard data, and history for all players.")
        }
    }

    // MARK: - Data Mutations

    /// Remove a round from its group (active or history) and delete from Supabase.
    private func removeRound(_ round: HomeRound) {
        for i in skinGameGroups.indices {
            if skinGameGroups[i].activeRound?.id == round.id {
                skinGameGroups[i].activeRound = nil
            }
            if skinGameGroups[i].concludedRound?.id == round.id {
                skinGameGroups[i].concludedRound = nil
            }
            skinGameGroups[i].roundHistory.removeAll { $0.id == round.id }
        }
        // Delete from Supabase (scores + round_players cascade), then refresh
        if authService.isAuthenticated {
            Task {
                do {
                    try await RoundService().deleteRound(roundId: round.id)
                    // Refresh groups so deleted round doesn't reappear from auto-refresh
                    if let userId = authService.currentUser?.id {
                        let refreshed = try await GroupService().loadGroups(userId: userId)
                        await MainActor.run {
                            skinGameGroups = refreshed
                        }
                    }
                } catch {
                    #if DEBUG
                    print("[HomeView] Failed to delete round from Supabase: \(error)")
                    #endif
                }
            }
        }
    }

    // MARK: - Invite Logic

    /// Load pending invites from Supabase and convert to HomeRound models.
    // MARK: - Home Poller (live card updates)

    private func startHomePoller() {
        stopHomePoller()
        homePoller = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            // Skip polling when not on Home tab
            guard selectedTab == .home else { return }
            Task { await pollHomeData() }
        }
    }

    private func stopHomePoller() {
        homePoller?.invalidate()
        homePoller = nil
    }

    private func pollHomeData() async {
        guard authService.isAuthenticated, let userId = authService.currentUser?.id else { return }
        // Poll invites
        await loadInvites(userId: userId)
        // Poll groups (active rounds, deleted rounds, member changes, etc.)
        do {
            let groupService = GroupService()
            let freshGroups = try await groupService.loadGroups(userId: userId)
            await MainActor.run {
                #if DEBUG
                let oldActive = skinGameGroups.compactMap { $0.activeRound?.id }
                let newActive = freshGroups.compactMap { $0.activeRound?.id }
                if oldActive != newActive {
                    print("[HomePoller] Active rounds changed: \(oldActive.count) → \(newActive.count)")
                }
                #endif
                skinGameGroups = freshGroups
            }
        } catch {
            #if DEBUG
            print("[HomePoller] Failed to poll: \(error)")
            #endif
        }
    }

    private func loadInvites(userId: UUID) async {
        var allInvites: [HomeRound] = []
        var allPendingInvites: [InviteDTO] = []

        // Load round invites
        do {
            let result = try await roundService.loadPendingInviteRounds(userId: userId)
            allPendingInvites = result.invites
            allInvites.append(contentsOf: result.rounds)
        } catch {
            #if DEBUG
            print("❌ Failed to load round invites: \(error)")
            #endif
        }

        // Load group invites
        do {
            let groupService = GroupService()
            let groupInvites = try await groupService.loadPendingGroupInvites(userId: userId)
            for invite in groupInvites {
                let homeRound = HomeRound(
                    id: invite.membership.id,
                    groupName: invite.group.name,
                    courseName: invite.group.lastCourseName ?? "",
                    players: invite.members,
                    status: .groupInvite,
                    currentHole: 0,
                    totalHoles: 18,
                    buyIn: Int(invite.group.buyIn),
                    skinsWon: 0,
                    totalSkins: 18,
                    yourSkins: 0,
                    invitedBy: invite.inviterName,
                    creatorId: 0,
                    startedAt: nil,
                    completedAt: nil,
                    scheduledDate: invite.group.scheduledDate
                )
                var mutableRound = homeRound
                mutableRound.supabaseGroupId = invite.group.id
                allInvites.append(mutableRound)
            }
        } catch {
            #if DEBUG
            print("❌ Failed to load group invites: \(error)")
            #endif
        }

        await MainActor.run {
            pendingInvites = allPendingInvites
            withAnimation(.easeOut(duration: 0.25)) {
                invitedRounds = allInvites
            }
        }
    }

    // MARK: - Clipboard Invite (post-install bridge)

    /// Called on appear. Uses `hasURLs` (no consent prompt) so we can
    /// decide whether to surface the "Join Skins Game" alert without
    /// triggering the "Allow Paste" dialog. The actual paste only
    /// happens when the user taps Join in the alert. Compares the
    /// current pasteboard `changeCount` against the last value the user
    /// already acknowledged so the alert doesn't re-fire for the same
    /// clipboard content — which previously happened on tab switches
    /// (HomeView @State resets when SwiftUI rebuilds the view).
    private func checkClipboardForInvite() {
        let current = UIPasteboard.general.changeCount
        clipboardInviteAvailable = UIPasteboard.general.hasURLs
            && current != clipboardInviteAckdChangeCount
    }

    /// Records the current pasteboard `changeCount` as acknowledged so the
    /// alert won't re-fire for this clipboard content — whether the user
    /// tapped Join or Cancel.
    private func markClipboardInviteAcknowledged() {
        clipboardInviteAckdChangeCount = UIPasteboard.general.changeCount
        didDismissClipboardInvite = true
        clipboardInviteAvailable = false
    }

    /// Invoked from the alert's Join button. Reads the clipboard — this is
    /// where iOS shows the single "Allow Paste" prompt — validates that
    /// the URL parses as a Carry invite, and routes through the same
    /// flow as a QR scan. Non-Carry URLs dismiss silently (no error
    /// toast for incidental clipboard contents).
    private func consumeClipboardInvite() {
        let urlOpt = UIPasteboard.general.url ?? UIPasteboard.general.string.flatMap(URL.init(string:))
        guard let url = urlOpt, GroupInviteParser.parse(url) != nil else {
            // Either the user denied the iOS Paste prompt or the clipboard
            // held something that wasn't a Carry invite. Surface a recovery
            // hint so they're not stranded.
            ToastManager.shared.error("Tap the QR icon to scan your invite.")
            markClipboardInviteAcknowledged()
            return
        }
        markClipboardInviteAcknowledged()
        handleScannedInvite(url.absoluteString)
    }

    /// Scanned QR payload handler. Mirrors `GroupsListView.handleScannedInvite`
    /// — the in-app scan is explicit consent so we skip the `invited → active`
    /// handshake and land the user directly inside the group with a success
    /// toast. The creator sees the standard "X joined" toast on their end
    /// when the new active member shows up in the next group refresh.
    private func handleScannedInvite(_ payload: String) {
        showQRScanner = false

        guard
            let url = URL(string: payload),
            let invite = GroupInviteParser.parse(url),
            let groupId = invite.groupId
        else {
            ToastManager.shared.error("That QR isn't a Carry invite.")
            return
        }

        Task {
            guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else { return }
            let service = GroupService()
            do {
                let groupName = try await service.joinGroupViaInvite(groupId: groupId, playerId: userId)
                await MainActor.run {
                    ToastManager.shared.success("Joined \(groupName)")
                    appRouter.shouldRefreshGroups = true
                    appRouter.pendingRoundGroupId = groupId
                    selectedTab = .skinGames
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.error("Couldn't join that group. Try again.")
                }
            }
        }
    }

    /// Accept an invite — update Supabase, add group locally, remove from invites.
    private func acceptInvite(_ round: HomeRound, retryCount: Int = 0) {
        acceptingInviteId = round.id
        Task {
            defer { Task { @MainActor in acceptingInviteId = nil } }
            do {
                if round.status == .groupInvite {
                    // Auto-match: if user was phone-invited, try to find their guest profile by name
                    if let groupId = round.supabaseGroupId,
                       let userId = authService.currentUser?.id {
                        let members = try? await GroupService().fetchGroupMembers(groupId: groupId)
                        let myMembership = members?.first(where: { $0.playerId == userId })
                        let isPhoneInvite = myMembership?.invitedPhone != nil && !(myMembership?.invitedPhone ?? "").isEmpty

                        if isPhoneInvite,
                           let guests = try? await GroupService().fetchGuestMembers(groupId: groupId),
                           !guests.isEmpty,
                           let userName = authService.currentUser?.displayName {
                            // Try auto-match by first name (case-insensitive)
                            let userFirst = userName.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
                            let matches = guests.filter { guest in
                                let guestFirst = guest.displayName.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
                                return !userFirst.isEmpty && guestFirst == userFirst
                            }
                            if matches.count == 1, let match = matches.first {
                                // Exact single match — auto-claim silently
                                try? await GuestProfileService().claimGuestProfile(
                                    guestId: match.id, realUserId: userId, groupId: groupId
                                )
                                #if DEBUG
                                print("[AutoClaim] Matched '\(userName)' → '\(match.displayName)', claimed automatically")
                                #endif
                            }
                            // Multiple matches or no match — skip claim, join without history
                        }
                    }

                    // Accept the invite
                    try await GroupService().acceptGroupInvite(membershipId: round.id)
                    // Brief delay to let Supabase propagate the status change
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if let userId = authService.currentUser?.id {
                        let refreshed = try await GroupService().loadGroups(userId: userId)
                        await MainActor.run {
                            skinGameGroups = refreshed
                        }
                    }
                    await MainActor.run {
                        withAnimation {
                            invitedRounds.removeAll { $0.id == round.id }
                            pendingInvites.removeAll { $0.id == round.id }
                        }
                        // Navigate to Games tab and open the group
                        selectedTab = .skinGames
                        if let groupId = round.supabaseGroupId {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                pendingActiveGroupId = groupId
                            }
                        }
                    }
                    ToastManager.shared.success("You joined \(round.groupName)!")
                } else {
                    // Round invite — use RoundService
                    try await roundService.acceptInvite(roundPlayerId: round.id)
                    if let userId = authService.currentUser?.id {
                        let refreshed = try await GroupService().loadGroups(userId: userId)
                        await MainActor.run {
                            skinGameGroups = refreshed
                        }
                    }
                    withAnimation {
                        invitedRounds.removeAll { $0.id == round.id }
                        pendingInvites.removeAll { $0.id == round.id }
                        selectedTab = .skinGames
                    }
                    ToastManager.shared.success("You're in!")
                }
            } catch {
                // Retry up to 2 times with a short delay (invite data may not be replicated yet)
                if retryCount < 2 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                    await MainActor.run { acceptInvite(round, retryCount: retryCount + 1) }
                    return
                }
                ToastManager.shared.error("Couldn't join group. Check your connection.")
                #if DEBUG
                print("❌ Failed to accept invite: \(error)")
                #endif
            }
        }
    }

    private var guestClaimSheet: some View {
        GuestClaimView(
            guests: guestClaimProfiles,
            groupName: pendingClaimRound?.groupName ?? "",
            onClaim: { guestId in
                claimGuestAndJoin(guestId: guestId)
            },
            onSkip: {
                skipClaimAndJoin()
            }
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgSecondary)
    }

    /// Claim a guest profile and join the group.
    private func claimGuestAndJoin(guestId: UUID) {
        guard let round = pendingClaimRound,
              let userId = authService.currentUser?.id,
              let groupId = round.supabaseGroupId else { return }

        // Clear state first, then dismiss to avoid stale data flash
        pendingClaimRound = nil
        guestClaimProfiles = []
        showGuestClaimSheet = false
        Task {
            do {
                try await GuestProfileService().claimGuestProfile(
                    guestId: guestId, realUserId: userId, groupId: groupId
                )
                let refreshed = try await GroupService().loadGroups(userId: userId)
                await MainActor.run {
                    skinGameGroups = refreshed
                    withAnimation {
                        invitedRounds.removeAll { $0.id == round.id }
                        pendingInvites.removeAll { $0.id == round.id }
                        selectedTab = .skinGames
                    }
                    ToastManager.shared.success("Welcome back! Your scores are here.")
                }
            } catch {
                ToastManager.shared.error("Couldn't claim profile. Try again.")
                #if DEBUG
                print("[HomeView] claimGuestAndJoin failed: \(error)")
                #endif
            }
        }
    }

    /// Skip guest claim and join the group as a new member.
    private func skipClaimAndJoin() {
        guard let round = pendingClaimRound else { return }

        showGuestClaimSheet = false
        Task {
            do {
                try await GroupService().acceptGroupInvite(membershipId: round.id)
                if let userId = authService.currentUser?.id {
                    let refreshed = try await GroupService().loadGroups(userId: userId)
                    await MainActor.run {
                        skinGameGroups = refreshed
                    }
                }
                withAnimation {
                    invitedRounds.removeAll { $0.id == round.id }
                    pendingInvites.removeAll { $0.id == round.id }
                    selectedTab = .skinGames
                }
                ToastManager.shared.success("You joined \(round.groupName)!")
            } catch {
                ToastManager.shared.error("Couldn't join group. Check your connection.")
            }
            await MainActor.run {
                pendingClaimRound = nil
                guestClaimProfiles = []
            }
        }
    }

    /// Decline an invite — update Supabase and remove from list.
    private func declineInvite(_ round: HomeRound) {
        Task {
            do {
                if round.status == .groupInvite {
                    // Group invite — use GroupService (membership ID stored in round.id)
                    try await GroupService().declineGroupInvite(membershipId: round.id)
                } else {
                    // Round invite — use RoundService
                    try await roundService.declineInvite(roundPlayerId: round.id)
                }
                withAnimation {
                    invitedRounds.removeAll { $0.id == round.id }
                    pendingInvites.removeAll { $0.id == round.id }
                }
                ToastManager.shared.success("Invite declined")
            } catch {
                #if DEBUG
                print("❌ Failed to decline invite: \(error)")
                #endif
                ToastManager.shared.error("Couldn't decline invite")
            }
        }
    }

    // MARK: - Empty State

    private var isEmptyState: Bool {
        activeRounds.isEmpty && invitedRounds.isEmpty && recentRounds.isEmpty
    }

    private var emptyHomeCallout: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            Image(systemName: "flag.fill")
                .font(.system(size: 40))
                .foregroundColor(Color.borderLight)

            Text("No Rounds Yet")
                .font(.carry.headlineBold)
                .foregroundColor(Color.textPrimary)

            Text("Create a skins game to get started,\nor wait for an invite from a friend.")
                .font(.carry.bodySM)
                .foregroundColor(Color.textDisabled)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button {
                selectedTab = .skinGames
            } label: {
                Text("Create a Skins Game")
                    .font(.carry.bodySMBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(Color.textPrimary)
                    )
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Greeting

    /// Build a clean RoundConfig from a HomeRound (unique ID so no cached scores load)
    private static func buildRoundConfig(from round: HomeRound) -> RoundConfig {
        let allPlayers = round.players
        // Group players by their assigned group number (from group_num column)
        let maxGroup = allPlayers.map(\.group).max() ?? 1
        var groups: [GroupConfig] = []
        if maxGroup > 1 {
            for g in 1...maxGroup {
                let playerIDs = allPlayers.filter { $0.group == g }.map(\.id)
                if !playerIDs.isEmpty {
                    groups.append(GroupConfig(id: g, startingSide: "front", playerIDs: playerIDs))
                }
            }
        }
        // Fallback: split into foursomes if no group assignments
        if groups.isEmpty {
            let groupSize = 4
            for i in stride(from: 0, to: allPlayers.count, by: groupSize) {
                let end = min(i + groupSize, allPlayers.count)
                let playerIDs = allPlayers[i..<end].map(\.id)
                groups.append(GroupConfig(id: groups.count + 1, startingSide: "front", playerIDs: Array(playerIDs)))
            }
        }
        if groups.isEmpty {
            groups.append(GroupConfig(id: 1, startingSide: "front", playerIDs: allPlayers.map(\.id)))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var config = RoundConfig(
            id: round.id.uuidString,  // unique per round — no stale cached scores
            number: 1,
            course: round.courseName,
            date: dateFormatter.string(from: Date()),
            buyIn: round.buyIn,
            gameType: "skins",
            skinRules: round.skinRules,
            teeBox: round.teeBox,
            groups: groups,
            creatorId: round.creatorId,
            groupName: round.groupName,
            players: allPlayers,
            holes: round.teeBox?.holes
        )
        config.supabaseRoundId = round.id
        config.supabaseGroupId = round.supabaseGroupId
        config.scoringMode = round.scoringMode
        config.isQuickGame = round.isQuickGame
        // HomeRound.scheduledDate is already resolved to the CURRENT user's
        // tee time (buildHomeRound picks teeTimes[userGroup-1] per memory).
        // Pipe through to the scorecard header's subtitle.
        config.scorerTeeTime = round.scheduledDate
        return config
    }

    private var greeting: String {
        let name = authService.currentUser?.displayName ?? ""
        let first = name.components(separatedBy: " ").first ?? ""
        if !first.isEmpty && first != "Player" {
            return "Hey, \(first)"
        }
        return "Hey"
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.carry.bodySMBold)
                .foregroundColor(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) item\(count == 1 ? "" : "s")")
    }

    // MARK: - Empty Card

    private func emptyCard(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.carry.bodyLG)
                .foregroundColor(Color.textDisabled)
                .accessibilityHidden(true)
            Text(text)
                .font(.carry.bodySM)
                .foregroundColor(Color.textDisabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Active Round Card (handles all 4 states)

    private func activeRoundCard(_ round: HomeRound) -> some View {
        // Derive card state from data. Concluded rounds are never "not started" even
        // if currentHole is 0 (e.g. on a member device where scores haven't synced yet).
        let isGameDone = round.isGameDone
        let hasPending = round.hasPendingResults
        let isNotStarted = round.currentHole == 0 && round.status != .concluded && !hasPending
        let isLiveScoring = !isNotStarted && !isGameDone && !hasPending
        let showGlow = !isNotStarted && !isGameDone  // States 2 & 3 only

        // Spectator mode: group member who isn't in this round's player list.
        // They can see the live card (follow winnings, current hole, etc.) but
        // cannot open the scorecard — tapping the card is a no-op for them.
        // Final results (Game Done / Pending) remain viewable for everyone.
        let isSpectator = !round.players.contains(where: { $0.id == currentUserId })

        return Button {
            if isGameDone {
                // State 4: Game Done → show final results (spectators can view)
                resultsRound = round
            } else if hasPending {
                // Some groups done, others still playing → show pending results
                resultsRound = round
            } else if isSpectator {
                // Spectator view — no navigation. Card remains visible and
                // updates in real time via polling, but the scorecard is
                // reserved for players actually in the round.
                return
            } else {
                // Live scoring → Go to scorecard
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    selectedRound = round
                }
            }
        } label: {
            VStack(spacing: 0) {
                // Top: tee time + badge
                HStack {
                    Text(round.teeTimeHeader)
                        .font(.carry.bodyLGBold)
                        .foregroundColor(Color.pureBlack)

                    Spacer()

                    if isGameDone {
                        // State 4: "✓ Game Done" green badge
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.successGreen)
                            Text("Game Done")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.successGreen)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.concludedGreen))
                    } else {
                        // States 1-3: Green LIVE pill (brand green)
                        let showHole = !isNotStarted
                        HStack(spacing: 5) {
                            PulsatingDot(color: Color.successGreen, size: 6)
                            Text("LIVE")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(Color.successGreen)

                            if showHole {
                                Text("Hole \(round.currentHole)")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundColor(Color.successGreen)
                            }
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 11)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.concludedGreen))
                    }
                }

                // Course name + group name
                VStack(alignment: .leading, spacing: 0) {
                    Text(round.courseName)
                        .font(.carry.bodySM)
                        .foregroundColor(Color(hexString: "#7A7A7E"))
                        .padding(.top, 6)
                    Text(round.groupName)
                        .font(.carry.bodySM)
                        .foregroundColor(Color(hexString: "#7A7A7E"))
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

                // Player pills — sorted by winnings (leader first)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(round.sortedPlayers) { player in
                            let winnings = round.playerWinnings[player.id] ?? 0
                            HStack(spacing: 6) {
                                PlayerAvatar(player: player, size: 28)
                                Text(player.shortName)
                                    .font(.carry.captionLG)
                                    .foregroundColor(Color.textPrimary)
                                    .lineLimit(1)
                                Text("$\(winnings)")
                                    .font(.carry.captionLGSemibold)
                                    .monospacedDigit()
                                    .foregroundColor(winnings > 0 ? Color.textPrimary : Color.textSecondary)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.bgSecondary))
                        }
                    }
                }
                .padding(.top, 8)

                // Bottom button — differs per state.
                // Spectators (not in the round's player list) don't get the
                // "LIVE Scorecard" button — only playing members can enter the
                // scorecard. Pending/Final result buttons stay visible for
                // everyone since those open a separate results sheet, not
                // the scorecard.
                if (isNotStarted || isLiveScoring) && !isSpectator {
                    // States 1 & 2: "LIVE Scorecard"
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            selectedRound = round
                        }
                    } label: {
                        HStack(spacing: 6) {
                            PulsatingDot(color: Color.successGreen, size: 6)
                            Text("LIVE Scorecard")
                                .font(.carry.bodySMSemibold)
                                .foregroundColor(Color.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 13).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.dividerLight, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)

                } else if isGameDone {
                    // State 4: Gold "Show Final Results · X Skins"
                    Button {
                        resultsRound = round
                    } label: {
                        HStack(spacing: 6) {
                            Text("Show Final Results")
                                .font(.carry.bodySMSemibold)
                                .foregroundColor(.white)
                            Text("·")
                                .font(.carry.bodySMSemibold)
                                .foregroundColor(.white.opacity(0.5))
                            Text("\(round.skinsWon) Skins")
                                .font(.carry.bodySMSemibold)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 13).fill(Color.textPrimary))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)

                } else if hasPending {
                    // State 3: "Show Pending Results · X/Y Groups"
                    Button {
                        resultsRound = round
                    } label: {
                        HStack(spacing: 6) {
                            PulsatingDot(color: Color.successGreen, size: 6)
                            Text("Show Pending Results · \(round.completedGroups)/\(round.totalGroups) Groups")
                                .font(.carry.bodySMSemibold)
                                .foregroundColor(Color.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 13).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.dividerLight, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)

                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        showGlow
                            ? Color.concludedGreen.opacity(activeCardPulse ? 0.8 : 0.3)
                            : Color.bgLight,
                        lineWidth: showGlow ? 2 : 1
                    )
                    .animation(showGlow ? .easeInOut(duration: 1.65).repeatForever(autoreverses: true) : .default, value: activeCardPulse)
            )
            .onAppear { if showGlow { activeCardPulse = true } }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(round.groupName), \(round.courseName), \(round.holeLabel), \(round.isGameDone ? "Game done" : "Live")")
        .accessibilityHint(round.isGameDone ? "Shows final results" : "Opens live scorecard")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Invite Card

    private func inviteCard(_ round: HomeRound) -> some View {
        VStack(spacing: 0) {
            // Invited by (above group name)
            if let inviter = round.invitedBy {
                HStack {
                    Text("\(inviter) invited you")
                        .font(.carry.caption)
                        .foregroundColor(Color.textTertiary)
                    Spacer()
                }
                .padding(.bottom, 2)
            }

            // Group name + buy-in
            HStack {
                Text(round.groupName)
                    .font(.carry.bodyLGBold)
                    .foregroundColor(Color.pureBlack)

                Spacer()

                HStack(spacing: 5) {
                    Text("$")
                        .font(.carry.microSM)
                        .foregroundColor(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.white.opacity(0.3)))
                    Text("\(round.buyIn) Buy-In")
                        .font(.carry.caption)
                        .foregroundColor(.white)
                }
                .padding(.leading, 4)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.goldMuted)
                )
            }

            // Course name + scheduled tee time
            HStack(spacing: 0) {
                Text(round.courseName)
                    .font(.carry.bodySM)
                    .foregroundColor(Color.textTertiary)
                Spacer()
            }
            .padding(.top, 6)

            if let label = round.scheduledLabel {
                HStack(spacing: 5) {
                    Text(label)
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }

            // Player pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(round.players) { player in
                        HStack(spacing: 6) {
                            PlayerAvatar(player: player, size: 28)
                            Text(player.shortName)
                                .font(.carry.captionLG)
                                .foregroundColor(Color.textPrimary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.bgSecondary)
                        )
                    }
                }
            }
            .padding(.top, 8)

            // Action buttons
            VStack(spacing: 0) {
                Button {
                    // Force paywall before joining. New downloaders see "Try It
                    // Free" (starts trial → grants Premium); lapsed users see
                    // "Subscribe". Either path flips isPremium → true, and the
                    // onChange handler auto-accepts the pending invite so the
                    // user doesn't have to tap Join twice.
                    if storeService.isPremium {
                        acceptInvite(round)
                    } else {
                        pendingInviteAfterPaywall = round
                        showPaywall = true
                    }
                } label: {
                    Group {
                        if acceptingInviteId == round.id {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Join Game")
                                .font(.carry.bodySMBold)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.textPrimary)
                    )
                }
                .buttonStyle(.plain)
                .disabled(acceptingInviteId == round.id)
                .accessibilityLabel("Join \(round.groupName)")
                .accessibilityHint("Accept invite and join the skins game")

                Button {
                    declineInvite(round)
                } label: {
                    Text("Decline")
                        .font(.carry.bodySMSemibold)
                        .foregroundColor(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decline invite from \(round.invitedBy ?? "unknown")")
                .accessibilityHint("Decline the game invite")
            }
            .padding(.top, 14)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    // MARK: - Recent Round Card

    private func recentRoundCard(_ round: HomeRound) -> some View {
        let winnings = round.playerWinnings[currentUserId] ?? 0

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(round.groupName)
                    .font(.carry.bodyLGBold)
                    .foregroundColor(Color.pureBlack)

                HStack(spacing: 6) {
                    Text("\(round.yourSkins) Skin\(round.yourSkins == 1 ? "" : "s") Won")
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textTertiary)

                    Text("\u{00B7}")
                        .foregroundColor(Color.textTertiary)

                    Text(round.timeLabel)
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textTertiary)
                }
                .padding(.top, 6)
            }

            Spacer()

            // Won pill — only shown when player won money
            if winnings > 0 {
                HStack(spacing: 5) {
                    Text("$")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.3)))
                    Text(verbatim: "\(winnings)")
                        .font(.carry.captionLG)
                        .foregroundColor(.white)
                }
                .padding(.leading, 5)
                .padding(.trailing, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.goldMuted)
                )
            }

            Image(systemName: "chart.bar.fill")
                .font(.system(size: 16))
                .foregroundColor(Color.goldMuted)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(round.groupName), \(round.courseName), \(round.yourSkins) skin\(round.yourSkins == 1 ? "" : "s") won\(winnings > 0 ? ", $\(winnings) won" : ""), view leaderboard")
    }

    // MARK: - Swipe to Leave

    private func swipeToLeaveWrapper<Content: View>(round: HomeRound, @ViewBuilder content: () -> Content) -> some View {
        let threshold: CGFloat = -80
        let currentOffset = swipeOffsets[round.id] ?? 0

        return ZStack(alignment: .trailing) {
            // Red action background — only visible when swiped
            if currentOffset < -1 {
                HStack {
                    Spacer()
                    Button {
                        roundToDelete = round
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.carry.bodyLGSemibold)
                            Text("Delete")
                                .font(.carry.micro)
                        }
                        .foregroundColor(.white)
                        .frame(width: 72, height: .infinity)
                    }
                    .frame(width: 72)
                    .frame(maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(hexString: "#E53935"))
                    )
                }
            }

            // Card content with drag + tap
            content()
                .offset(x: swipeOffsets[round.id] ?? 0)
                .onTapGesture {
                    if (swipeOffsets[round.id] ?? 0) < -10 {
                        // Swiped open — close it
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            swipeOffsets[round.id] = 0
                        }
                    } else {
                        leaderboardRound = round
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            // Only handle horizontal swipes (ignore vertical scrolling)
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let drag = min(0, value.translation.width)
                            swipeOffsets[round.id] = max(drag, threshold - 10)
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    swipeOffsets[round.id] = 0
                                }
                                return
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if (swipeOffsets[round.id] ?? 0) < threshold / 2 {
                                    swipeOffsets[round.id] = threshold
                                } else {
                                    swipeOffsets[round.id] = 0
                                }
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @State private var swipeOffsets: [UUID: CGFloat] = [:]

}

// MARK: - Leaderboard Sheet

struct LeaderboardSheet: View {
    @EnvironmentObject var storeService: StoreService
    let round: HomeRound
    var groupRoundHistory: [HomeRound] = []
    @State private var selectedTab: Int = 0  // 0 = Last Round, 1 = All Time
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leaderboard")
                        .font(Font.system(size: 24, weight: .bold))
                        .foregroundColor(Color.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    let subtitle = [round.groupName, round.courseName.isEmpty ? nil : round.courseName]
                        .compactMap { $0 }.joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Font.system(size: 16, weight: .medium))
                            .foregroundColor(Color.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(Font.system(size: 22, weight: .medium))
                    .foregroundColor(Color.goldMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 24)

            // Last Round | All Time tabs (skins groups only — quick games have a single round).
            // All Time is free for everyone — reading historical data should never be paywalled.
            if !round.isQuickGame {
                HStack(spacing: 16) {
                    ForEach(Array(["Last Round", "All Time"].enumerated()), id: \.offset) { idx, label in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedTab = idx
                            }
                        } label: {
                            Text(label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(selectedTab == idx ? .white : Color.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(
                                    Capsule().fill(selectedTab == idx ? Color.textPrimary : Color.bgPrimary)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(selectedTab == idx ? "Selected" : "")
                        .accessibilityAddTraits(selectedTab == idx ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            // Round summary (only for Last Round tab)
            if selectedTab == 0 {
                HStack(spacing: 24) {
                    statPill(label: "POT", value: "$\(round.potTotal)")
                    statPill(label: "SKINS", value: "\(round.skinsWon)/\(round.totalSkins)")
                    statPill(label: "PER SKIN", value: round.skinValue > 0 ? "~$\(round.skinValue)" : "—")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            // Column headers
            HStack(spacing: 0) {
                Text("Player")
                    .font(Font.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.textSecondary)
                Spacer()
                Text("Skins")
                    .font(Font.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.textSecondary)
                    .frame(width: 60, alignment: .center)
                Text("Won")
                    .font(Font.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.textSecondary)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            Rectangle()
                .fill(Color.bgPrimary)
                .frame(height: 1)
                .padding(.horizontal, 24)

            // Player rows — filtered to winners on Last Round tab
            ScrollView {
                VStack(spacing: 0) {
                    let visible = visibleRankedPlayers
                    ForEach(Array(visible.enumerated()), id: \.element.player.id) { idx, entry in
                        leaderboardRow(player: entry.player, skins: entry.skins, won: entry.won)

                        if idx < visible.count - 1 {
                            Rectangle()
                                .fill(Color.borderFaint)
                                .frame(height: 1)
                                .padding(.leading, 82)
                                .padding(.trailing, 24)
                        }
                    }

                    // Inline Round Stats — Last Round tab only. Shows every
                    // player (including 0-skins) so the full field is visible
                    // here even though the leaderboard above is winners-only.
                    if selectedTab == 0 {
                        leaderboardStatsSection()
                    }
                }
            }

            Spacer()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Visible Players (leaderboard filter)

    /// Ranked players for the current tab. Last Round is narrowed to actual
    /// skin winners (matches post-round Results); All Time keeps everyone.
    private var visibleRankedPlayers: [RankedEntry] {
        guard selectedTab == 0 else { return rankedPlayers }
        return rankedPlayers.filter { $0.skins > 0 }
    }

    // MARK: - Inline Round Stats

    /// Per-player inline stats block. Avoids a network fetch by using only
    /// what HomeRound carries — score-stats line (birdies/bogeys) is
    /// deliberately skipped because per-hole scores aren't on HomeRound.
    private func leaderboardStatsSection() -> some View {
        let statsPlayers = round.players
            .filter { !$0.isPendingAccept }
            .sorted { a, b in
                let aWon = round.playerWinnings[a.id] ?? 0
                let bWon = round.playerWinnings[b.id] ?? 0
                if aWon != bWon { return aWon > bWon }
                let aSkins = round.playerWonHoles[a.id]?.count ?? 0
                let bSkins = round.playerWonHoles[b.id]?.count ?? 0
                if aSkins != bSkins { return aSkins > bSkins }
                return a.name < b.name
            }

        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color.bgPrimary)
                .frame(height: 8)

            // Section header — matches the "Leaderboard" header style so
            // Stats reads as its own labeled section under the table above.
            Text("Stats")
                .font(Font.system(size: 24, weight: .bold))
                .foregroundColor(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(statsPlayers.enumerated()), id: \.element.id) { idx, player in
                    leaderboardStatsRow(player: player)

                    if idx < statsPlayers.count - 1 {
                        Rectangle()
                            .fill(Color.borderFaint)
                            .frame(height: 1)
                            .padding(.leading, 82)
                            .padding(.trailing, 24)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func leaderboardStatsRow(player: Player) -> some View {
        let skins = round.playerWonHoles[player.id]?.count ?? 0
        let holesWon = round.playerWonHoles[player.id] ?? []
        let money = round.playerWinnings[player.id] ?? 0
        let pops = leaderboardPops(handicap: player.handicap, teeBox: round.teeBox)
        let hcLabel = leaderboardHandicapLabel(player.handicap)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                PlayerAvatar(player: player, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.shortName)
                        .font(.carry.bodySemibold)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(hcLabel) · \(pops) pops")
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Match the leaderboard "Won" column: same font weight/size
                // and 72pt fixed trailing-aligned width so the amounts line
                // up vertically with the rows above.
                Text(moneyLabel(money))
                    .font(Font.system(size: 17, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(
                        money > 0 ? Color.goldMuted
                        : money < 0 ? Color.textDisabled
                        : Color.borderSoft
                    )
                    .frame(width: 72, alignment: .trailing)
            }

            Group {
                if skins > 0 {
                    let holesList = holesWon.sorted().map { "\($0)" }.joined(separator: ", ")
                    HStack(spacing: 4) {
                        Text("\(skins) Skin\(skins == 1 ? "" : "s")")
                            .foregroundColor(Color.textSecondary)
                        Text("\u{00B7}")
                            .foregroundColor(Color.textDisabled)
                        Text("Holes \(holesList)")
                            .foregroundColor(Color.textPrimary)
                    }
                } else {
                    Text("No Skins")
                        .foregroundColor(Color.textSecondary)
                }
            }
            .font(.carry.bodySM)
            .padding(.leading, 50) // align under the name (38 avatar + 12 spacing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func leaderboardPops(handicap: Double, teeBox: TeeBox?) -> Int {
        let playingHcp: Int
        if let teeBox, teeBox.slopeRating > 0, teeBox.courseRating > 0 {
            playingHcp = teeBox.playingHandicap(
                forIndex: handicap,
                percentage: round.skinRules.handicapPercentage
            )
        } else {
            playingHcp = Int(handicap.rounded())
        }
        return max(playingHcp, 0)
    }

    private func leaderboardHandicapLabel(_ hcp: Double) -> String {
        if hcp.sign == .minus {
            return String(format: "+%.1f", -hcp)
        }
        return String(format: "%.1f", hcp)
    }

    private func moneyLabel(_ amount: Int) -> String {
        if amount > 0 { return "$\(amount)" }
        if amount < 0 { return "-$\(-amount)" }
        return "$0"
    }

    // MARK: - Ranked Players

    private struct RankedEntry {
        let player: Player
        let skins: Int
        let won: Int
    }

    private var rankedPlayers: [RankedEntry] {
        let rounds = selectedTab == 1 ? groupRoundHistory : [round]
        // Aggregate across selected rounds
        var stats: [Int: (skins: Int, won: Int)] = [:]
        var allPlayers: [Player] = []
        for r in rounds {
            for player in r.players {
                if !allPlayers.contains(where: { $0.id == player.id }) {
                    allPlayers.append(player)
                }
                let skins = r.playerWonHoles[player.id]?.count ?? 0
                let won = r.playerWinnings[player.id] ?? 0
                let existing = stats[player.id] ?? (skins: 0, won: 0)
                stats[player.id] = (skins: existing.skins + skins, won: existing.won + won)
            }
        }
        return allPlayers.map { player in
            let s = stats[player.id] ?? (skins: 0, won: 0)
            return RankedEntry(player: player, skins: s.skins, won: s.won)
        }
        .sorted { a, b in
            if a.won != b.won { return a.won > b.won }
            if a.skins != b.skins { return a.skins > b.skins }
            return a.player.name < b.player.name
        }
    }

    // MARK: - Components

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .font(Font.system(size: 12, weight: .semibold))
                .tracking(CarryTracking.wide)
                .foregroundColor(Color.borderSoft)
            Text(value)
                .font(Font.system(size: 18, weight: .semibold))
                .foregroundColor(Color.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.bgSecondary)
        )
    }

    private func leaderboardRow(player: Player, skins: Int, won: Int) -> some View {
        HStack(spacing: 12) {
            PlayerAvatar(player: player, size: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.shortName)
                    .font(Font.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                Text(formatHandicap(player.handicap))
                    .font(Font.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.borderMedium)
            }

            Spacer()

            Text("\(skins)")
                .font(Font.system(size: 17, weight: skins > 0 ? .bold : .medium))
                .foregroundColor(skins > 0 ? Color.textPrimary : Color.borderSoft)
                .frame(width: 60, alignment: .center)

            Text("$\(won)")
                .font(Font.system(size: 17, weight: .medium))
                .foregroundColor(won > 0 ? Color.goldMuted : Color.borderSoft)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }
}

// MARK: - Pending Results Sheet

struct ResultsSheet: View {
    let round: HomeRound
    var currentUserId: Int = 1
    var onSaveResults: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    private var isFinal: Bool {
        round.isGameDone || round.status == .concluded || round.status == .completed
    }

    /// Show Save Round Results only for concluded rounds the user can still finalize.
    /// Completed rounds are already saved → no action button. Pending rounds can't be
    /// saved until all groups finish → button hidden.
    private var canSaveResults: Bool {
        round.status == .concluded && onSaveResults != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — course name (no date), with share button in top-right
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 5) {
                    Text(isFinal ? "Final Results" : "Pending Results")
                        .font(Font.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                    Text(round.courseName)
                        .font(Font.system(size: 16, weight: .medium))
                        .foregroundColor(Color.textSecondary)
                }
                .frame(maxWidth: .infinity)

                if onShare != nil {
                    Button { onShare?() } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(Font.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.textSecondary)
                            .frame(width: 43, height: 43)
                            .background(Circle().fill(Color.bgSecondary))
                    }
                    .padding(.trailing, 24)
                    .accessibilityLabel("Share results")
                }
            }
            .padding(.top, 34)
            .padding(.bottom, 14)

            // Scrollable content
            ScrollView {
                VStack(spacing: 0) {
                    // Hero — shown only when the viewer is a participant.
                    // Spectators (non-playing group members viewing the round)
                    // skip the big-circle hero entirely — it's meaningless as
                    // a "featured you" moment when you weren't in the round.
                    // They just see the winners list directly.
                    let viewerIsParticipant = round.players.contains(where: { $0.id == currentUserId })
                    if viewerIsParticipant,
                       let currentPlayer = round.players.first(where: { $0.id == currentUserId }) {
                        FinalResultsHero(
                            player: currentPlayer,
                            skinsWon: round.playerWonHoles[currentPlayer.id]?.count ?? 0,
                            winAmount: round.playerWinnings[currentPlayer.id] ?? 0,
                            isFinal: isFinal
                        )
                        .padding(.bottom, 24)
                    }

                    if isFinal {
                        // FINAL — per-player winners list (excludes current user, shown in hero).
                        // Uses the shared FinalResultsWinnerRow component so RoundCompleteView and
                        // ResultsSheet render identically.
                        let winners = otherWinners
                        ForEach(Array(winners.enumerated()), id: \.element.id) { idx, entry in
                            FinalResultsWinnerRow(
                                player: entry.player,
                                skins: entry.skins,
                                amount: entry.amount
                            )

                            if idx < winners.count - 1 {
                                FinalResultsRowDivider()
                            }
                        }

                        // Round Stats — every active player (winners + 0-skins
                        // participants) with HC · pops, Skins · Holes, and
                        // money. Spectators get the full picture here; in-round
                        // players see the same data + birdies/bogeys on the
                        // RoundCompleteView (which has access to scores).
                        resultsStatsSection
                            .padding(.top, 24)
                    } else {
                        // PENDING — per-hole won skins + pending leaders
                        let wonHoles = wonHoleRows
                        if !wonHoles.isEmpty {
                            Text("\(wonHoles.count) Won Skin\(wonHoles.count == 1 ? "" : "s")")
                                .font(Font.system(size: 18, weight: .semibold))
                                .foregroundColor(Color.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 10)
                        }

                        ForEach(Array(wonHoles.enumerated()), id: \.element.id) { idx, entry in
                            wonHoleRow(entry)

                            if idx < wonHoles.count - 1 {
                                Rectangle()
                                    .fill(Color.borderFaint)
                                    .frame(height: 1)
                                    .padding(.leading, 82)
                                    .padding(.trailing, 24)
                            }
                        }

                        if !round.pendingHoleLeaders.isEmpty {
                            HStack(spacing: 7) {
                                PulsatingDot(color: Color.successGreen)
                                Text("Pending")
                                    .font(Font.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 35)
                            .padding(.bottom, 10)

                            ForEach(round.pendingHoleLeaders) { pending in
                                pendingHoleRow(pending)

                                if pending.holeNum != round.pendingHoleLeaders.last?.holeNum {
                                    Rectangle()
                                        .fill(Color.borderFaint)
                                        .frame(height: 1)
                                        .padding(.leading, 82)
                                        .padding(.trailing, 24)
                                }
                            }
                        }
                    }
                }
            }

            if canSaveResults {
                FinalResultsPrimaryButton(title: "Save Round Results") {
                    onSaveResults?()
                }
            } else {
                Spacer()
            }
        }
    }

    // MARK: - Per-player winners (final state)

    private struct WinnerEntry: Identifiable {
        let id: Int         // player.id
        let player: Player
        let skins: Int
        let amount: Int
    }

    /// All players who won at least one skin, excluding the current user (they're the hero).
    /// Sorted by amount descending, then by name.
    private var otherWinners: [WinnerEntry] {
        round.playerWonHoles.compactMap { (playerId, holes) -> WinnerEntry? in
            guard playerId != currentUserId,
                  !holes.isEmpty,
                  let player = round.players.first(where: { $0.id == playerId }) else { return nil }
            let amount = round.playerWinnings[playerId] ?? 0
            return WinnerEntry(id: playerId, player: player, skins: holes.count, amount: amount)
        }
        .sorted { a, b in
            if a.amount != b.amount { return a.amount > b.amount }
            return a.player.name < b.player.name
        }
    }

    // MARK: - Won Skins (per-hole rows)

    private struct WonHoleEntry: Identifiable {
        let id: String  // "playerId-holeNum"
        let player: Player
        let holeNum: Int
        let isYou: Bool
    }

    /// Flatten playerWonHoles into individual hole rows, sorted by hole number
    /// Excludes current user's skins (already shown in the hero header)
    private var wonHoleRows: [WonHoleEntry] {
        var entries: [WonHoleEntry] = []
        let currentId = currentUserId
        for (playerId, holes) in round.playerWonHoles {
            guard playerId != currentId else { continue }
            guard let player = round.players.first(where: { $0.id == playerId }) else { continue }
            for hole in holes {
                entries.append(WonHoleEntry(
                    id: "\(playerId)-\(hole)",
                    player: player,
                    holeNum: hole,
                    isYou: false
                ))
            }
        }
        return entries.sorted { $0.holeNum < $1.holeNum }
    }

    // MARK: - Components

    /// Won hole row — matches pending hole row format
    private func wonHoleRow(_ entry: WonHoleEntry) -> some View {
        HStack(spacing: 12) {
            PlayerAvatar(player: entry.player, size: 38)

            HStack(spacing: 5) {
                Text(entry.player.shortName)
                    .font(Font.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                if entry.isYou {
                    Text("You")
                        .font(Font.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.textDark)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.textDark.opacity(0.10)))
                }
            }

            Spacer()

            Text("Hole \(entry.holeNum)")
                .font(Font.system(size: 16, weight: .medium))
                .foregroundColor(Color.textPrimary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func pendingHoleRow(_ pending: HomeRound.PendingHoleLeader) -> some View {
        HStack(spacing: 12) {
            if let leader = pending.leader {
                PlayerAvatar(player: leader, size: 38, showPulse: true, badgeNumber: pending.score)

                Text(leader.name)
                    .font(Font.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.textPrimary.opacity(0.55))
                    .lineLimit(1)
            } else {
                ZStack {
                    Circle()
                        .fill(Color(hexString: "#F5F3EE"))
                        .frame(width: 38, height: 38)
                    PulsatingDot(color: Color.goldMuted, size: 7)
                }
            }

            Spacer()

            Text("Hole \(pending.holeNum)")
                .font(Font.system(size: 16, weight: .medium))
                .foregroundColor(Color.textPrimary.opacity(0.55))
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func formatHandicap(_ h: Double) -> String {
        h == h.rounded() ? String(format: "%.0f", h) : String(format: "%.1f", h)
    }

    // MARK: - Inline Round Stats (every active player)

    /// Full-field stats block: avatar + name + HC · pops + "X Skins · Holes
    /// N, N, N" (or "No Skins") + money. Uses only HomeRound data — no
    /// per-hole scores, so birdies/bogeys are skipped. Matches the pattern
    /// used in the Leaderboard sheet's Last Round tab. Leaderboard
    /// unification TODO tracks consolidating all three copies of this.
    @ViewBuilder
    private var resultsStatsSection: some View {
        let statsPlayers = round.players
            .filter { !$0.isPendingAccept }
            .sorted { a, b in
                let aWon = round.playerWinnings[a.id] ?? 0
                let bWon = round.playerWinnings[b.id] ?? 0
                if aWon != bWon { return aWon > bWon }
                let aSkins = round.playerWonHoles[a.id]?.count ?? 0
                let bSkins = round.playerWonHoles[b.id]?.count ?? 0
                if aSkins != bSkins { return aSkins > bSkins }
                return a.name < b.name
            }

        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.bgPrimary)
                .frame(height: 8)

            Text("Stats")
                .font(Font.system(size: 24, weight: .bold))
                .foregroundColor(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(statsPlayers.enumerated()), id: \.element.id) { idx, player in
                    resultsStatsRow(player: player)

                    if idx < statsPlayers.count - 1 {
                        Rectangle()
                            .fill(Color.borderFaint)
                            .frame(height: 1)
                            .padding(.leading, 82)
                            .padding(.trailing, 24)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func resultsStatsRow(player: Player) -> some View {
        let skins = round.playerWonHoles[player.id]?.count ?? 0
        let holesWon = round.playerWonHoles[player.id] ?? []
        let money = round.playerWinnings[player.id] ?? 0
        let pops = resultsPops(handicap: player.handicap, teeBox: round.teeBox)
        let hcLabel = resultsHandicapLabel(player.handicap)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                PlayerAvatar(player: player, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.shortName)
                        .font(.carry.bodySemibold)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(hcLabel) · \(pops) pops")
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(resultsMoneyLabel(money))
                    .font(Font.system(size: 17, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(
                        money > 0 ? Color.goldMuted
                        : money < 0 ? Color.textDisabled
                        : Color.borderSoft
                    )
                    .frame(width: 72, alignment: .trailing)
            }

            Group {
                if skins > 0 {
                    let holesList = holesWon.sorted().map { "\($0)" }.joined(separator: ", ")
                    HStack(spacing: 4) {
                        Text("\(skins) Skin\(skins == 1 ? "" : "s")")
                            .foregroundColor(Color.textSecondary)
                        Text("\u{00B7}")
                            .foregroundColor(Color.textDisabled)
                        Text("Holes \(holesList)")
                            .foregroundColor(Color.textPrimary)
                    }
                } else {
                    Text("No Skins")
                        .foregroundColor(Color.textSecondary)
                }
            }
            .font(.carry.bodySM)
            .padding(.leading, 50) // align under the name (38 avatar + 12 spacing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func resultsPops(handicap: Double, teeBox: TeeBox?) -> Int {
        let playingHcp: Int
        if let teeBox, teeBox.slopeRating > 0, teeBox.courseRating > 0 {
            playingHcp = teeBox.playingHandicap(
                forIndex: handicap,
                percentage: round.skinRules.handicapPercentage
            )
        } else {
            playingHcp = Int(handicap.rounded())
        }
        return max(playingHcp, 0)
    }

    private func resultsHandicapLabel(_ hcp: Double) -> String {
        if hcp.sign == .minus {
            return String(format: "+%.1f", -hcp)
        }
        return String(format: "%.1f", hcp)
    }

    private func resultsMoneyLabel(_ amount: Int) -> String {
        if amount > 0 { return "$\(amount)" }
        if amount < 0 { return "-$\(-amount)" }
        return "$0"
    }
}

// MARK: - Pulsating Dot

struct PulsatingDot: View {
    var color: Color = Color.successGreen
    var size: CGFloat = 7
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(pulse ? 0.15 : 0.4))
                .frame(width: size * 1.8, height: size * 1.8)
                .scaleEffect(pulse ? 1.6 : 1.0)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 1.8, height: size * 1.8)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - HomeRound Identifiable for fullScreenCover

extension HomeRound: Equatable {
    static func == (lhs: HomeRound, rhs: HomeRound) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Previews

#if DEBUG
#Preview("1 - Empty (first run)") {
    HomeView(
        selectedTab: .constant(.home),
        skinGameGroups: .constant([]),
        pendingActiveGroupId: .constant(nil)
    )
    .environmentObject(AuthService())
    .environmentObject(StoreService())
}

#Preview("2 - Populated") {
    HomeView(
        selectedTab: .constant(.home),
        skinGameGroups: .constant(SavedGroup.demo),
        pendingActiveGroupId: .constant(nil)
    )
    .environmentObject(AuthService())
    .environmentObject(StoreService())
}
#endif
