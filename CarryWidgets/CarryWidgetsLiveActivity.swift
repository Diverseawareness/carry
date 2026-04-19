//
//  CarryWidgetsLiveActivity.swift
//  CarryWidgets
//
//  Dark-mode mirror of the active round card on the home screen.
//  Same 4 states: notStarted / live / pending / done.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Brand / Color helpers (self-contained for the widget target)

private extension Color {
    static let carryGold = Color(red: 0.831, green: 0.627, blue: 0.090)   // #D4A017
    static let liveGreen = Color(red: 0.30, green: 0.85, blue: 0.40)

    /// Minimal hex parser so this file doesn't depend on the main app's Color+Hex.
    init(hex: String) {
        let scrubbed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: scrubbed).scanHexInt64(&int)
        let r, g, b: Double
        switch scrubbed.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >>  8) & 0xFF) / 255
            b = Double( int        & 0xFF) / 255
        default:
            r = 0.5; g = 0.5; b = 0.5
        }
        self = Color(red: r, green: g, blue: b)
    }
}

// MARK: - Widget

struct CarryWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CarryRoundAttributes.self) { context in
            // Lock Screen / Banner — whole banner taps through to the round.
            LockScreenView(context: context)
                .widgetURL(deepLinkURL(for: context.attributes, state: context.state.state))
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (long-press)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.courseName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let group = context.attributes.groupName {
                            Text(group)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StateBadge(state: context.state.state, hole: context.state.currentHole)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PillBar(players: context.state.players, maxVisible: 3)
                        .padding(.top, 26)
                }
            } compactLeading: {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                if let me = context.state.players.first(where: { $0.isCurrentUser }) {
                    Text("$\(me.winnings)")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            } minimal: {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
            }
            .widgetURL(deepLinkURL(for: context.attributes, state: context.state.state))
            .keylineTint(Color.carryGold)
        }
    }
}

// MARK: - Deep link

/// Build the `carry://round/<id>[?group=<groupId>]` URL the lock-screen banner
/// and Dynamic Island use to deep-link back into the app. The app routes to the
/// scorecard for live/pending/notStarted; the round-complete sheet auto-shows
/// when the round is concluded.
private func deepLinkURL(
    for attributes: CarryRoundAttributes,
    state: CarryRoundAttributes.RoundState
) -> URL? {
    var components = URLComponents()
    components.scheme = "carry"
    components.host = "round"
    components.path = "/\(attributes.roundId)"
    if let groupId = attributes.groupId {
        components.queryItems = [URLQueryItem(name: "group", value: groupId)]
    }
    return components.url
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let context: ActivityViewContext<CarryRoundAttributes>

    private var state: CarryRoundAttributes.ContentState { context.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: course name + state badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.courseName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let group = context.attributes.groupName {
                        Text(group)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                StateBadge(state: state.state, hole: state.currentHole)
            }

            // Row 2: pill bar. 4 per row so 8-player groups stay on one row,
            // and the overall content fits within iOS' lock-screen max height.
            PillBar(players: state.players, maxVisible: 4)

            // Row 3: state-dependent footer
            footer
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var footer: some View {
        switch state.state {
        case .pending:
            HStack(spacing: 6) {
                PulseDot(color: .orange, size: 6)
                Text("Show Pending Results")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
            }
        case .done:
            HStack(spacing: 6) {
                // Static green dot — mirrors the .pending PulseDot so both
                // footers share the same left alignment and visual rhythm.
                Circle()
                    .fill(Color.liveGreen)
                    .frame(width: 6, height: 6)
                Text("Show Final Results")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text("·")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                Text("\(state.skinsWon) Skins")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
            }
        case .live, .notStarted:
            EmptyView()
        }
    }
}

// MARK: - State Badge (mirrors the green LIVE pill + ✓ Game Done)

private struct StateBadge: View {
    let state: CarryRoundAttributes.RoundState
    let hole: Int

    var body: some View {
        // Matched HStack spacing (5) and text typography (10pt heavy) across
        // both variants so the pill's visual weight stays constant when the
        // round transitions live → done.
        switch state {
        case .done:
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.liveGreen)
                Text("GAME DONE")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.liveGreen)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.liveGreen.opacity(0.15)))
            .overlay(Capsule().strokeBorder(Color.liveGreen.opacity(0.35), lineWidth: 1))

        case .notStarted, .live, .pending:
            HStack(spacing: 5) {
                PulseDot(color: .liveGreen, size: 6)
                Text("LIVE")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.liveGreen)
                if state != .notStarted, hole > 0 {
                    Text("Hole \(hole)")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.liveGreen)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.liveGreen.opacity(0.15)))
            .overlay(Capsule().strokeBorder(Color.liveGreen.opacity(0.35), lineWidth: 1))
        }
    }
}

// MARK: - Pill Bar (reordering HStack — mirrors CashGamesBar)

private struct PillBar: View {
    let players: [CarryRoundAttributes.PillPlayer]
    /// Max pills per row (full width). Rows are hard-capped at 2.
    let maxVisible: Int

    private var maxTotal: Int { maxVisible * 2 }

    private var visible: [CarryRoundAttributes.PillPlayer] {
        if players.count <= maxTotal { return players }
        return Array(players.prefix(maxTotal - 1))
    }
    private var overflow: Int { max(0, players.count - visible.count) }

    private var row1: [CarryRoundAttributes.PillPlayer] {
        Array(visible.prefix(maxVisible))
    }
    private var row2: [CarryRoundAttributes.PillPlayer] {
        Array(visible.dropFirst(maxVisible))
    }
    private var hasSecondRow: Bool {
        !row2.isEmpty || overflow > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(row1) { player in
                    PlayerPill(player: player)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                Spacer(minLength: 0)
            }
            if hasSecondRow {
                HStack(spacing: 6) {
                    ForEach(row2) { player in
                        PlayerPill(player: player)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    if overflow > 0 {
                        OverflowPill(count: overflow)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(
            .spring(response: 0.5, dampingFraction: 0.8),
            value: visible.map(\.id)
        )
    }
}

private struct OverflowPill: View {
    let count: Int

    var body: some View {
        // Match PlayerPill's vertical padding so both pills share the same
        // rendered height (13pt font + 5pt vertical padding on both).
        Text("+\(count)")
            .font(.system(size: 13, weight: .bold))
            .monospacedDigit()
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}

private struct PlayerPill: View {
    let player: CarryRoundAttributes.PillPlayer

    var body: some View {
        HStack(spacing: 6) {
            Text(player.shortName)
                .font(.system(size: 13, weight: player.isCurrentUser ? .semibold : .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("$\(player.winnings)")
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundColor(player.winnings > 0 ? .white : .white.opacity(0.5))
                .contentTransition(.numericText())
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}

// MARK: - PulseDot (SwiftUI-only approximation of the live indicator)

private struct PulseDot: View {
    let color: Color
    let size: CGFloat
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulse ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

// MARK: - Previews

extension CarryRoundAttributes {
    fileprivate static var preview: CarryRoundAttributes {
        CarryRoundAttributes(
            roundId: "preview",
            courseName: "Pebble Beach",
            groupName: "Saturday Skins",
            totalHoles: 18,
            groupId: nil
        )
    }
}

extension CarryRoundAttributes.ContentState {
    fileprivate static var liveRound: CarryRoundAttributes.ContentState {
        .init(
            currentHole: 7,
            state: .live,
            players: [
                .init(id: 1, shortName: "Daniel S.",    initials: "DS", colorHex: "#D4A017", winnings: 12, isCurrentUser: true),
                .init(id: 2, shortName: "Garret B.",    initials: "GB", colorHex: "#4A90D9", winnings: 8,  isCurrentUser: false),
                .init(id: 3, shortName: "Adi R.",       initials: "AR", colorHex: "#E05555", winnings: 4,  isCurrentUser: false),
                .init(id: 4, shortName: "Bartholomew S.", initials: "BS", colorHex: "#2ECC71", winnings: 0, isCurrentUser: false),
            ],
            completedGroups: 0,
            totalGroups: 1,
            skinsWon: 3,
            waitingOnGroup: nil
        )
    }

    fileprivate static var pending: CarryRoundAttributes.ContentState {
        var s = liveRound
        s.state = .pending
        s.waitingOnGroup = "other groups"
        return s
    }

    fileprivate static var done: CarryRoundAttributes.ContentState {
        var s = liveRound
        s.state = .done
        s.skinsWon = 9
        return s
    }
}

#Preview("Island Expanded", as: .dynamicIsland(.expanded), using: CarryRoundAttributes.preview) {
    CarryWidgetsLiveActivity()
} contentStates: {
    CarryRoundAttributes.ContentState.liveRound
    CarryRoundAttributes.ContentState.pending
    CarryRoundAttributes.ContentState.done
}

#Preview("Lock Screen", as: .content, using: CarryRoundAttributes.preview) {
    CarryWidgetsLiveActivity()
} contentStates: {
    CarryRoundAttributes.ContentState.liveRound
    CarryRoundAttributes.ContentState.pending
    CarryRoundAttributes.ContentState.done
}
