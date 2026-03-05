import SwiftUI

// MARK: - Home Round Model

enum HomeRoundStatus: String {
    case active, invited, completed
}

struct HomeRound: Identifiable {
    let id: UUID
    let groupName: String
    let players: [Player]
    let status: HomeRoundStatus
    let currentHole: Int       // 0 for not started
    let totalHoles: Int        // 9 or 18
    let buyIn: Int
    let skinsWon: Int          // total skins won so far
    let totalSkins: Int        // total skins available
    let yourSkins: Int         // current user's skins won
    let yourWinnings: Int      // current user's $ won
    let invitedBy: String?     // name of person who invited (for .invited)
    let startedAt: Date?
    let completedAt: Date?

    var skinValue: Int {
        guard totalSkins > 0 else { return 0 }
        return (buyIn * players.count) / totalSkins
    }

    var potTotal: Int { buyIn * players.count }

    var holeLabel: String {
        if currentHole == 0 { return "Not started" }
        if status == .completed { return "Final" }
        return "Hole \(currentHole) of \(totalHoles)"
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

    // MARK: Demo Data

    static let demoActive: [HomeRound] = [
        HomeRound(
            id: UUID(),
            groupName: "Friday Meetings",
            players: Array(Player.allPlayers.prefix(8)),
            status: .active,
            currentHole: 7,
            totalHoles: 18,
            buyIn: 50,
            skinsWon: 3,
            totalSkins: 18,
            yourSkins: 1,
            yourWinnings: 22,
            invitedBy: nil,
            startedAt: Calendar.current.date(byAdding: .hour, value: -2, to: Date()),
            completedAt: nil
        ),
    ]

    static let demoInvited: [HomeRound] = [
        HomeRound(
            id: UUID(),
            groupName: "Saturday Scramble",
            players: Array(Player.allPlayers.prefix(4)),
            status: .invited,
            currentHole: 0,
            totalHoles: 18,
            buyIn: 100,
            skinsWon: 0,
            totalSkins: 18,
            yourSkins: 0,
            yourWinnings: 0,
            invitedBy: "Garret",
            startedAt: nil,
            completedAt: nil
        ),
    ]

    static let demoRecent: [HomeRound] = [
        HomeRound(
            id: UUID(),
            groupName: "Friday Meetings",
            players: Array(Player.allPlayers.prefix(8)),
            status: .completed,
            currentHole: 18,
            totalHoles: 18,
            buyIn: 50,
            skinsWon: 14,
            totalSkins: 18,
            yourSkins: 3,
            yourWinnings: 66,
            invitedBy: nil,
            startedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date()),
            completedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date())
        ),
        HomeRound(
            id: UUID(),
            groupName: "Thursday Boys",
            players: Array(Player.allPlayers.suffix(4)),
            status: .completed,
            currentHole: 18,
            totalHoles: 18,
            buyIn: 25,
            skinsWon: 12,
            totalSkins: 18,
            yourSkins: 0,
            yourWinnings: 0,
            invitedBy: nil,
            startedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date()),
            completedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date())
        ),
    ]
}

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @State private var activeRounds: [HomeRound] = HomeRound.demoActive
    @State private var invitedRounds: [HomeRound] = HomeRound.demoInvited
    @State private var recentRounds: [HomeRound] = HomeRound.demoRecent
    @State private var selectedRound: HomeRound?

    var body: some View {
        ZStack {
            Color(hex: "#F0F0F0").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(greeting)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(Color(hex: "#1A1A1A"))
                            Text("Golf Skins Tracker")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "#999999"))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                    // MARK: Active Rounds
                    sectionHeader("ACTIVE ROUNDS", count: activeRounds.count)

                    if activeRounds.isEmpty {
                        emptyCard("No active rounds", icon: "figure.golf")
                    } else {
                        ForEach(activeRounds) { round in
                            activeRoundCard(round)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                    }

                    // MARK: Pending Invites
                    if !invitedRounds.isEmpty {
                        sectionHeader("INVITES", count: invitedRounds.count)
                            .padding(.top, 16)

                        ForEach(invitedRounds) { round in
                            inviteCard(round)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                    }

                    // MARK: Recent Rounds
                    sectionHeader("RECENT", count: recentRounds.count)
                        .padding(.top, 16)

                    if recentRounds.isEmpty {
                        emptyCard("No recent rounds", icon: "clock")
                    } else {
                        ForEach(recentRounds) { round in
                            recentRoundCard(round)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                    }

                    Spacer().frame(height: 20)
                }
            }
        }
        .fullScreenCover(item: $selectedRound) { round in
            RoundCoordinatorView(
                initialMembers: round.players,
                groupName: round.groupName,
                currentUserId: 1,
                onExit: { selectedRound = nil }
            )
        }
    }

    // MARK: - Greeting

    private var greeting: String {
        let name = authService.currentUser?.displayName ?? "Carry"
        let hour = Calendar.current.component(.hour, from: Date())
        if name != "Carry" && name != "Player" {
            return "Hey, \(name.components(separatedBy: " ").first ?? name)"
        }
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(Color(hex: "#BBBBBB"))

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color(hex: "#CCCCCC")))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    // MARK: - Empty Card

    private func emptyCard(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "#CCCCCC"))
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#CCCCCC"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Active Round Card

    private func activeRoundCard(_ round: HomeRound) -> some View {
        Button {
            selectedRound = round
        } label: {
            VStack(spacing: 0) {
                // Top: group name + live badge + hole
                HStack {
                    // Live dot + group name
                    HStack(spacing: 8) {
                        liveDot

                        Text(round.groupName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                    }

                    Spacer()

                    Text(round.holeLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#2ECC71"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color(hex: "#2ECC71").opacity(0.1))
                        )
                }

                // Avatar stack + time
                HStack {
                    miniAvatarStack(round.players)

                    Text(round.timeLabel)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#BBBBBB"))

                    Spacer()
                }
                .padding(.top, 10)

                // Divider
                Rectangle()
                    .fill(Color(hex: "#F0F0F0"))
                    .frame(height: 1)
                    .padding(.top, 12)

                // Bottom: pot info + your skins
                HStack {
                    // Pot info
                    VStack(alignment: .leading, spacing: 2) {
                        Text("$\(round.potTotal) pot")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                        Text("\(round.skinsWon) of \(round.totalSkins) skins won")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#AAAAAA"))
                    }

                    Spacer()

                    // Your skins
                    if round.yourSkins > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("+$\(round.yourWinnings)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Color(hex: "#2ECC71"))
                            Text("\(round.yourSkins) skin\(round.yourSkins == 1 ? "" : "s")")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#AAAAAA"))
                        }
                    } else {
                        Text("No skins yet")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#CCCCCC"))
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#CCCCCC"))
                        .padding(.leading, 8)
                }
                .padding(.top, 12)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(hex: "#2ECC71").opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Invite Card

    private func inviteCard(_ round: HomeRound) -> some View {
        VStack(spacing: 0) {
            // Top: group name + invited by
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(round.groupName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "#1A1A1A"))

                    if let inviter = round.invitedBy {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#C4A450"))
                            Text("\(inviter) invited you")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#999999"))
                        }
                    }
                }

                Spacer()

                Text("$\(round.buyIn) buy-in")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#C4A450"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color(hex: "#C4A450").opacity(0.1))
                    )
            }

            // Players
            HStack {
                miniAvatarStack(round.players)

                Text("\(round.players.count) players · \(round.totalHoles) holes")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#BBBBBB"))

                Spacer()
            }
            .padding(.top, 10)

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    withAnimation { invitedRounds.removeAll { $0.id == round.id } }
                } label: {
                    Text("Decline")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "#999999"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color(hex: "#E0E0E0"), lineWidth: 1)
                        )
                }

                Button {
                    withAnimation {
                        var joined = round
                        joined = HomeRound(
                            id: round.id, groupName: round.groupName, players: round.players,
                            status: .active, currentHole: round.currentHole, totalHoles: round.totalHoles,
                            buyIn: round.buyIn, skinsWon: 0, totalSkins: round.totalHoles,
                            yourSkins: 0, yourWinnings: 0, invitedBy: nil,
                            startedAt: Date(), completedAt: nil
                        )
                        activeRounds.append(joined)
                        invitedRounds.removeAll { $0.id == round.id }
                    }
                } label: {
                    Text("Join")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(hex: "#1A1A1A"))
                        )
                }
            }
            .padding(.top, 14)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(hex: "#C4A450").opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Recent Round Card

    private func recentRoundCard(_ round: HomeRound) -> some View {
        Button {
            selectedRound = round
        } label: {
            HStack(spacing: 14) {
                // Result badge
                ZStack {
                    Circle()
                        .fill(round.yourSkins > 0
                              ? Color(hex: "#2ECC71").opacity(0.1)
                              : Color(hex: "#F0F0F0"))
                    if round.yourSkins > 0 {
                        Text("+$\(round.yourWinnings)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "#2ECC71"))
                    } else {
                        Text("$0")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "#BBBBBB"))
                    }
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(round.groupName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "#1A1A1A"))

                    HStack(spacing: 6) {
                        if round.yourSkins > 0 {
                            Text("\(round.yourSkins) skin\(round.yourSkins == 1 ? "" : "s") won")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#2ECC71"))
                        } else {
                            Text("No skins")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#BBBBBB"))
                        }

                        Text("·")
                            .foregroundColor(Color(hex: "#DDDDDD"))

                        Text(round.timeLabel)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#BBBBBB"))
                    }
                }

                Spacer()

                // Player count
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#CCCCCC"))
                    Text("\(round.players.count)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#CCCCCC"))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#CCCCCC"))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Components

    private var liveDot: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#2ECC71").opacity(0.3))
                .frame(width: 12, height: 12)
            Circle()
                .fill(Color(hex: "#2ECC71"))
                .frame(width: 7, height: 7)
        }
    }

    private func miniAvatarStack(_ players: [Player]) -> some View {
        let display = Array(players.prefix(5))
        return ZStack {
            ForEach(Array(display.enumerated()), id: \.offset) { idx, player in
                ZStack {
                    Circle()
                        .fill(Color(hex: player.color).opacity(0.09))
                    Circle()
                        .strokeBorder(Color(hex: player.color).opacity(0.25), lineWidth: 1)
                    Circle()
                        .strokeBorder(.white, lineWidth: 1.5)
                    Text(player.avatar)
                        .font(.system(size: 11))
                }
                .frame(width: 24, height: 24)
                .offset(x: CGFloat(idx) * 12)
            }
        }
        .frame(width: CGFloat(min(display.count, 5) - 1) * 12 + 24, alignment: .leading)
        .padding(.trailing, 6)
    }
}

// MARK: - HomeRound Identifiable for fullScreenCover

extension HomeRound: Equatable {
    static func == (lhs: HomeRound, rhs: HomeRound) -> Bool {
        lhs.id == rhs.id
    }
}
