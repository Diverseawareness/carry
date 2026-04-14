import SwiftUI

/// Reusable scorer assignment component — search Carry users or invite via phone.
///
/// Three states:
/// - **Empty**: Shows search field with typeahead
/// - **Confirmed**: Shows player avatar + name + handicap + X button
/// - **Invited**: Shows player name + phone + "Invited" badge
///
/// Usage:
///   ScorerAssignmentView(
///       scorer: $scorer,
///       excludeProfileIds: [creatorId],
///       groupLabel: "Group 2"
///   )
struct ScorerAssignmentView: View {
    /// The assigned scorer. Nil = empty/search state.
    @Binding var scorer: ScorerSlot

    /// Profile IDs to exclude from search results (creator, already-assigned scorers).
    var excludeProfileIds: Set<UUID> = []

    /// Label for the group (used in invite SMS context).
    var groupLabel: String = ""

    /// Default color for invited (non-Carry) scorers. Defaults to gray.
    var defaultColor: String = "#999999"

    /// When true, shows confirmed state without clear button (used for creator/group 1).
    var readOnly: Bool = false

    // MARK: - Internal State

    @State private var searchText = ""
    @State private var searchResults: [ProfileDTO] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var phoneText = ""
    @State private var phoneName = ""

    @FocusState private var focused: ScorerField?

    private enum ScorerField: Hashable {
        case search
        case phone
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 5) {
            switch scorer.state {
            case .empty:
                searchField
            case .confirmed:
                confirmedRow
            case .invited:
                invitedRow
            }
        }
    }

    // MARK: - Confirmed Row

    private var confirmedRow: some View {
        HStack(spacing: 6) {
            PlayerAvatar(player: scorer.asPlayer, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(scorer.name)
                    .font(.carry.bodySemibold)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                let subtitle = [scorer.homeClub, !scorer.handicap.isEmpty ? scorer.handicap : nil]
                    .compactMap { $0 }.joined(separator: " · ")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.carry.bodySM)
                        .foregroundColor(Color(hexString: "#BFC0C2"))
                }
            }

            Spacer()

            if !readOnly {
                Button {
                    clearScorer()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color.textDisabled)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove scorer")
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(height: 58)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight, lineWidth: 1))
    }

    // MARK: - Invited Row

    private var invitedRow: some View {
        HStack(spacing: 6) {
            PlayerAvatar(player: scorer.asPlayer, size: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(scorer.name)
                    .font(.carry.bodySMSemibold)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                if let phone = scorer.phoneNumber {
                    Text(Self.formatPhone(phone))
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textPrimary)
                }
            }

            Spacer()

            Text("Invited")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hexString: "#E38049"))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(hexString: "#FFE7CA")))
                .overlay(Capsule().strokeBorder(Color(hexString: "#FFD4BE"), lineWidth: 0.88))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(height: 58)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight, lineWidth: 1))
    }

    // MARK: - Search Field + Results

    private var searchField: some View {
        VStack(spacing: 5) {
            // Search input
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(Color.textDisabled)

                TextField("Search by name or Invite", text: $searchText)
                    .font(.carry.bodyLG)
                    .foregroundColor(Color.textPrimary)
                    .focused($focused, equals: .search)
                    .onChange(of: searchText) { _, newValue in
                        debounceSearch(query: newValue)
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color.textDisabled)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .carryInput(focused: focused == .search, bare: true)

            // Results
            resultsCards
        }
    }

    @ViewBuilder
    private var resultsCards: some View {
        let hasResults = !searchResults.isEmpty
        let showInviteOption = searchText.count >= 2 && !isSearching

        // Carry user results
        if hasResults {
            ForEach(searchResults.prefix(5)) { profile in
                Button {
                    selectScorer(profile: profile)
                } label: {
                    HStack(spacing: 10) {
                        PlayerAvatar(player: Player(from: profile), size: 34)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(profile.firstName) \(profile.lastName)".trimmingCharacters(in: .whitespaces))
                                .font(.carry.bodySemibold)
                                .foregroundColor(Color.textPrimary)
                            let subtitle = [profile.homeClub, profile.handicap != 0 ? String(format: "%.1f", profile.handicap) : nil]
                                .compactMap { $0 }.joined(separator: " · ")
                            if !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.carry.bodySM)
                                    .foregroundColor(Color(hexString: "#BFC0C2"))
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .frame(height: 58)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }

        // Inline SMS invite
        if showInviteOption {
            VStack(alignment: .leading, spacing: 12) {
                Text("Send Invite to \"\(searchText)\"")
                    .font(.carry.bodySMSemibold)
                    .foregroundColor(Color.textTertiary)

                HStack(spacing: 10) {
                    Image(systemName: "iphone")
                        .font(.system(size: 14))
                        .foregroundColor(Color.textDisabled)

                    TextField("Enter Phone Number", text: $phoneText)
                        .font(.carry.bodyLG)
                        .foregroundColor(Color.textPrimary)
                        .keyboardType(.phonePad)
                        .focused($focused, equals: .phone)
                        .onChange(of: phoneText) { _, newValue in
                            let digits = newValue.filter { $0.isNumber }
                            if digits.count > 10 {
                                phoneText = String(digits.prefix(10))
                            }
                        }
                        .onAppear {
                            phoneName = searchText
                            phoneText = ""
                        }

                    let digits = phoneText.filter { $0.isNumber }
                    Button {
                        sendInvite()
                    } label: {
                        Text("Send")
                            .font(.carry.bodySMSemibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(Capsule().fill(digits.count >= 10 ? Color.textPrimary : Color.borderSubtle))
                    }
                    .buttonStyle(.plain)
                    .disabled(digits.count < 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight, lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func debounceSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            searchResults = []
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do {
                let results = try await PlayerSearchService.shared.searchPlayers(query: trimmed)
                let filtered = results.filter { !excludeProfileIds.contains($0.id) }
                await MainActor.run {
                    searchResults = filtered
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }

    private func selectScorer(profile: ProfileDTO) {
        scorer = ScorerSlot(
            name: "\(profile.firstName) \(profile.lastName)".trimmingCharacters(in: .whitespaces),
            handicap: String(format: "%.1f", profile.handicap),
            profileId: profile.id,
            color: profile.color,
            avatarUrl: profile.avatarUrl,
            homeClub: profile.homeClub
        )
        searchText = ""
        searchResults = []
        focused = nil
    }

    private func sendInvite() {
        let digits = phoneText.filter { $0.isNumber }
        guard digits.count >= 10 else { return }

        let name = phoneName.trimmingCharacters(in: .whitespaces)

        scorer = ScorerSlot(
            name: name.isEmpty ? Self.formatPhone(digits) : name,
            color: defaultColor,
            isPendingInvite: true,
            phoneNumber: digits
        )

        // Open native SMS
        let body = "Score our skins game on Carry! Download: https://carryapp.site"
        let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "sms:\(digits)&body=\(encoded)") {
            UIApplication.shared.open(url)
        }

        searchText = ""
        searchResults = []
        phoneText = ""
        phoneName = ""
        focused = nil
    }

    private func clearScorer() {
        scorer = ScorerSlot()
        searchText = ""
        searchResults = []
        phoneText = ""
        phoneName = ""
    }

    // MARK: - Helpers

    static func formatPhone(_ digits: String) -> String {
        guard digits.count >= 10 else { return digits }
        let last10 = String(digits.suffix(10))
        let area = last10.prefix(3)
        let mid = last10.dropFirst(3).prefix(3)
        let end = last10.suffix(4)
        return "(\(area)) \(mid)-\(end)"
    }
}

// MARK: - ScorerSlot Model

/// Lightweight scorer data that bridges between the search UI and the parent's data model.
struct ScorerSlot: Equatable {
    var name: String = ""
    var handicap: String = ""
    var profileId: UUID? = nil
    var color: String = "#999999"
    var isPendingInvite: Bool = false
    var phoneNumber: String? = nil
    var avatarUrl: String? = nil
    var homeClub: String? = nil

    enum State {
        case empty, confirmed, invited
    }

    var state: State {
        if isPendingInvite { return .invited }
        if profileId != nil { return .confirmed }
        if !name.isEmpty { return .confirmed }
        return .empty
    }

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// Convert to Player for PlayerAvatar rendering.
    var asPlayer: Player {
        Player(
            id: Player.stableId(from: profileId ?? UUID()),
            name: name,
            initials: initials,
            color: color,
            handicap: Double(handicap) ?? 0,
            avatar: "",
            group: 1,
            ghinNumber: nil,
            venmoUsername: nil,
            avatarImageName: nil,
            avatarUrl: avatarUrl,
            isPendingInvite: isPendingInvite,
            profileId: profileId
        )
    }
}
