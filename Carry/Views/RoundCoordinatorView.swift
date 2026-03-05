import SwiftUI

struct RoundCoordinatorView: View {
    let initialMembers: [Player]
    let currentUserId: Int
    var onExit: (() -> Void)?

    enum Phase: Equatable {
        case setup
        case starting
        case active
    }

    init(initialMembers: [Player] = Player.allPlayers, groupName: String = "Friday Meetings", currentUserId: Int = 1, onExit: (() -> Void)? = nil) {
        self.initialMembers = initialMembers
        self._groupName = State(initialValue: groupName)
        self.currentUserId = currentUserId
        self.onExit = onExit
    }

    @State private var phase: Phase = .setup
    @State private var roundConfig: RoundConfig?
    @State private var groups: [[Player]] = []
    @State private var startingSides: [String] = []
    @State private var groupName: String = "Friday Meetings"
    @State private var showSplashLeaderboard = false

    // Splash animation states
    @State private var showFlag = false
    @State private var showTitle = false
    @State private var showDetails = false
    @State private var showStats = false
    @State private var pulseFlag = false

    var body: some View {
        ZStack {
            switch phase {
            case .setup:
                GroupManagerView(allMembers: initialMembers, onBack: onExit) { config in
                    self.roundConfig = config
                    self.groups = config.groups.map { gc in
                        gc.playerIDs.compactMap { pid in Player.allPlayers.first(where: { $0.id == pid }) }
                    }
                    self.startingSides = config.groups.map(\.startingSide)
                    withAnimation(.easeInOut(duration: 0.4)) {
                        phase = .starting
                    }
                    // Stagger the splash animations
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { showFlag = true }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeOut(duration: 0.4)) { showTitle = true }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.easeOut(duration: 0.4)) { showDetails = true }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeOut(duration: 0.4)) { showStats = true }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulseFlag = true
                        }
                    }
                }
                .transition(.opacity)

            case .starting:
                roundStartedSplash
                    .transition(.opacity)

            case .active:
                ScorecardView(config: roundConfig ?? .default, onBack: {
                    let config = roundConfig ?? .default
                    switch config.role(for: currentUserId) {
                    case .creator:
                        // Creator goes back to Group Manager
                        showFlag = false
                        showTitle = false
                        showDetails = false
                        showStats = false
                        pulseFlag = false
                        withAnimation(.easeInOut(duration: 0.3)) {
                            phase = .setup
                        }
                    case .participant:
                        // Participant exits round to Home
                        onExit?()
                    }
                }, currentUserId: currentUserId)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
    }

    // MARK: - All Players

    private var allPlayers: [Player] {
        groups.flatMap { $0 }
    }

    // MARK: - Round Started Splash

    private var roundStartedSplash: some View {
        let totalPlayers = allPlayers.count
        let groupCount = groups.count

        return ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "#1A1A1A"), Color(hex: "#2D2D2D")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Flag icon with pulse
                ZStack {
                    // Glow ring
                    Circle()
                        .fill(Color(hex: "#C4A450").opacity(0.08))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseFlag ? 1.15 : 1.0)

                    Circle()
                        .fill(Color(hex: "#C4A450").opacity(0.15))
                        .frame(width: 88, height: 88)

                    Image(systemName: "flag.fill")
                        .font(.system(size: 36))
                        .foregroundColor(Color(hex: "#C4A450"))
                }
                .scaleEffect(showFlag ? 1.0 : 0.3)
                .opacity(showFlag ? 1 : 0)

                Spacer().frame(height: 32)

                // "Round Started"
                Text("Round Started")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 12)

                Spacer().frame(height: 8)

                // Player + group count
                Text("\(totalPlayers) players \u{00B7} \(groupCount) group\(groupCount == 1 ? "" : "s")")
                    .font(.system(size: 16))
                    .foregroundColor(Color.white.opacity(0.5))
                    .opacity(showDetails ? 1 : 0)
                    .offset(y: showDetails ? 0 : 8)

                Spacer().frame(height: 48)

                // Stats cards
                VStack(spacing: 12) {
                    statCard(
                        icon: "dollarsign.circle.fill",
                        title: "$\(roundConfig?.buyIn ?? 50) Buy-in",
                        subtitle: "Net Skins \u{00B7} \(roundConfig?.skinRules.carries == true ? "Carries" : "No Carries")"
                    )

                    statCard(
                        icon: "person.3.fill",
                        title: "\(groupCount) Group\(groupCount == 1 ? "" : "s") Ready",
                        subtitle: "All players notified"
                    )

                    // Leaderboard card — tappable
                    Button {
                        showSplashLeaderboard = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color(hex: "#C4A450"))
                                .frame(width: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Leaderboard")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("All-time standings")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.white.opacity(0.4))
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.2))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
                .opacity(showStats ? 1 : 0)
                .offset(y: showStats ? 0 : 16)

                Spacer()

                // "Go to Scorecard" button
                Button {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        phase = .active
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Go to Scorecard")
                            .font(.system(size: 17, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#1A1A1A"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#C4A450"))
                    )
                }
                .padding(.horizontal, 40)
                .opacity(showStats ? 1 : 0)

                Spacer().frame(height: 16)

                // Back to groups link
                Button {
                    showFlag = false
                    showTitle = false
                    showDetails = false
                    showStats = false
                    pulseFlag = false
                    withAnimation(.easeInOut(duration: 0.3)) {
                        phase = .setup
                    }
                } label: {
                    Text("Back to Groups")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                }
                .opacity(showStats ? 1 : 0)

                Spacer().frame(height: 40)
            }
        }
        .sheet(isPresented: $showSplashLeaderboard) {
            splashLeaderboardSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Splash Leaderboard Sheet

    private var splashLeaderboardSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leaderboard")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    Text(groupName)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#999999"))
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "#C4A450"))
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)

            // Season label
            HStack {
                Text("ALL TIME")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(Color(hex: "#BBBBBB"))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Column headers
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 28)
                Text("Player")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#999999"))
                Spacer()
                Text("Skins")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#999999"))
                    .frame(width: 50, alignment: .center)
                Text("Net")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#999999"))
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color(hex: "#F0F0F0"))
                .frame(height: 1)
                .padding(.horizontal, 24)

            // Player rows
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(allPlayers.enumerated()), id: \.element.id) { rank, player in
                        leaderboardRow(rank: rank + 1, player: player)

                        if rank < allPlayers.count - 1 {
                            Rectangle()
                                .fill(Color(hex: "#F5F5F5"))
                                .frame(height: 1)
                                .padding(.leading, 68)
                                .padding(.trailing, 24)
                        }
                    }
                }
            }

            Spacer()

            // Empty state
            VStack(spacing: 8) {
                Text("No rounds played yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#999999"))
                Text("Stats will appear here after your first round.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#CCCCCC"))
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Leaderboard Row

    private func leaderboardRow(rank: Int, player: Player) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 13, weight: rank <= 3 ? .bold : .regular))
                .foregroundColor(rank <= 3 ? Color(hex: "#C4A450") : Color(hex: "#BBBBBB"))
                .frame(width: 22, alignment: .center)

            ZStack {
                Circle()
                    .fill(Color(hex: player.color).opacity(0.09))
                Circle()
                    .strokeBorder(Color(hex: player.color).opacity(0.25), lineWidth: 1.5)
                Text(player.avatar)
                    .font(.system(size: 14))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text("HCP \(String(format: "%.1f", player.handicap))")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#CCCCCC"))
            }

            Spacer()

            Text("0")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "#BBBBBB"))
                .frame(width: 50, alignment: .center)

            Text("$0")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "#BBBBBB"))
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    // MARK: - Stat Card

    private func statCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: "#C4A450"))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.4))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
