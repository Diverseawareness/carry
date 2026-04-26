import SwiftUI

// MARK: - Data Models

struct ShareCardData {
    let courseName: String
    let date: Date
    let teeName: String?
    let handicapPct: Int
    let entries: [ShareCardEntry]
    let potTotal: Int
    let buyIn: Int
}

struct ShareCardEntry: Identifiable {
    let id = UUID()
    let name: String
    let initials: String
    let color: String
    let skinsWon: Int
    let moneyAmount: Int // positive = won, negative = lost
    var avatarImage: UIImage? = nil // pre-downloaded photo, nil = use branded initials

    /// First name + last initial: "Daniel S."
    var shortName: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0]) \(parts[1].prefix(1))."
        }
        return name
    }
}

// MARK: - Share Card Theme

enum ShareCardTheme {
    case dark
    case light

    var background: Color {
        switch self {
        case .dark: return Color(red: 0.1, green: 0.1, blue: 0.1)
        case .light: return .white
        }
    }
    var primaryText: Color {
        switch self {
        case .dark: return .white
        case .light: return Color(hexString: "#1A1A1A")
        }
    }
    var secondaryText: Color {
        switch self {
        case .dark: return Color(white: 0.55)
        case .light: return Color(hexString: "#6E6E73")
        }
    }
    var tertiaryText: Color {
        switch self {
        case .dark: return Color(white: 0.4)
        case .light: return Color(hexString: "#AEAEB2")
        }
    }
    var divider: Color {
        switch self {
        case .dark: return Color(white: 0.2)
        case .light: return Color(hexString: "#E5E5EA")
        }
    }
    var gold: Color {
        Color(red: 0.85, green: 0.75, blue: 0.35)
    }
    var lossText: Color {
        switch self {
        case .dark: return Color(white: 0.45)
        case .light: return Color(hexString: "#999999")
        }
    }
}

// MARK: - Share Card View

struct ResultsShareCard: View {
    let data: ShareCardData
    var theme: ShareCardTheme = .dark
    var showAppStoreBadge: Bool = true
    /// Fixed render width. Defaults to 390 so the image-rendering path (social
    /// share card) produces consistent dimensions. Pass nil to let the card
    /// flex to its container — used when embedding in the invite sheet.
    var fixedWidth: CGFloat? = 390

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.bottom, 20)

            dividerLine

            leaderboardSection
                .padding(.top, 16)
                .padding(.bottom, 20)

            if data.potTotal > 0 {
                potSection
                    .padding(.bottom, 20)
            }

            dividerLine
            footerSection
                .padding(.top, 16)
        }
        .padding(28)
        .frame(width: fixedWidth)
        .background(theme.background)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(data.courseName)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(theme.primaryText)

            HStack(spacing: 8) {
                Text(Self.dateFormatter.string(from: data.date))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.secondaryText)

                if let tee = data.teeName {
                    Text("\u{00B7}")
                        .foregroundColor(theme.tertiaryText)
                    Text("\(tee) at \(data.handicapPct)%")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Leaderboard

    private var leaderboardSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PLAYER")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
                    .tracking(1.2)
                Spacer()
                Text("SKINS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
                    .tracking(1.2)
                    .frame(width: 50, alignment: .center)
                Text("MONEY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
                    .tracking(1.2)
                    .frame(width: 65, alignment: .trailing)
            }
            .padding(.bottom, 12)

            ForEach(Array(data.entries.enumerated()), id: \.element.id) { index, entry in
                playerRow(entry: entry, rank: index + 1)
                    .padding(.vertical, 8)
            }
        }
    }

    private func playerRow(entry: ShareCardEntry, rank: Int) -> some View {
        let isWinner = rank == 1 && entry.skinsWon > 0

        return HStack(spacing: 12) {
            if isWinner {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12))
                    .foregroundColor(theme.gold)
                    .frame(width: 18)
            } else {
                Text("\(rank)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
                    .frame(width: 18)
            }

            shareCardAvatar(entry: entry)

            Text(entry.shortName)
                .font(.system(size: 15, weight: isWinner ? .bold : .medium))
                .foregroundColor(isWinner ? theme.gold : theme.primaryText)
                .lineLimit(1)

            Spacer()

            Text("\(entry.skinsWon)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.primaryText)
                .frame(width: 50, alignment: .center)

            Text(moneyText(entry.moneyAmount))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(entry.moneyAmount > 0 ? theme.gold : theme.lossText)
                .frame(width: 65, alignment: .trailing)
        }
    }

    private func moneyText(_ amount: Int) -> String {
        if amount > 0 { return "$\(amount)" }
        if amount < 0 { return "-$\(abs(amount))" }
        return "$0"
    }

    @ViewBuilder
    private func shareCardAvatar(entry: ShareCardEntry) -> some View {
        if let photo = entry.avatarImage {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color(hexString: "#BCF0B5"))
                Circle()
                    .strokeBorder(Color(hexString: "#A3E09C"), lineWidth: 1.5)
                Text(entry.initials)
                    .font(.custom("ANDONESI-Regular", size: 15))
                    .foregroundColor(Color(hexString: "#064102"))
            }
            .frame(width: 32, height: 32)
        }
    }

    // MARK: - Pot

    private var potSection: some View {
        HStack(spacing: 8) {
            Text("Pot: $\(data.potTotal)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.secondaryText)
            Text("\u{00B7}")
                .foregroundColor(theme.tertiaryText)
            Text("$\(data.buyIn)/player")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Image(theme == .dark ? "logo-side-limegreen" : "logo-side-darkgreen")
                .resizable()
                .scaledToFit()
                .frame(height: 28)

            Spacer()

            if showAppStoreBadge {
                appStoreBadge
            }
        }
    }

    private var appStoreBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "apple.logo")
                .font(.system(size: 16))
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 0) {
                Text("Download on the")
                    .font(.system(size: 7, weight: .regular))
                    .foregroundColor(.white)
                Text("App Store")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(theme == .dark ? 0.3 : 0), lineWidth: 1)
        )
    }

    // MARK: - Divider

    private var dividerLine: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(height: 1)
    }
}
