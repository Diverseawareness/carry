import SwiftUI

// MARK: - Manage Members Sheet (extracted for performance — no @Binding to parent)

struct ManageMembersSheet: View {
    let allAvailable: [Player]
    let initialSelectedIDs: Set<Int>
    let initialNextGuestID: Int
    var supabaseGroupId: UUID? = nil
    let onCancel: () -> Void
    let onDone: (ManageMembersResult) -> Void

    struct ManageMembersResult {
        let selectedIDs: Set<Int>
        let newGuests: [Player]
        let nextGuestID: Int
        /// Local player IDs for members who were long-press-removed inside
        /// the sheet. The sheet already persisted the server-side
        /// `status='removed'` update; the parent uses this list to drop the
        /// same rows from its in-memory group so the UI stays in sync
        /// without waiting for the next 30s refresh.
        let removedPlayerIds: Set<Int>
    }

    @State private var selectedIDs: Set<Int>
    @State private var localGuests: [Player] = []
    @State private var nextGuestID: Int
    @State private var memberSearchText = ""
    @State private var onlineSearchResults: [ProfileDTO] = []
    @State private var isSearchingOnline = false
    @State private var onlineSearchTask: Task<Void, Never>?
    @State private var showInviteModal = false
    @State private var invitePhone = ""
    @State private var inviteSent = false
    @State private var showMembersTip = true
    /// Players the user long-pressed → confirmed → removed. Held locally
    /// so the avatar tile disappears immediately; propagated to the parent
    /// on Done via `ManageMembersResult.removedPlayerIds`.
    @State private var locallyRemovedIds: Set<Int> = []
    /// Triggers the "Remove {name}" iOS-native confirmation alert.
    @State private var memberToRemove: Player? = nil

    enum Field: Hashable { case memberSearch, invitePhone }
    @FocusState private var focused: Field?
    private var isSearchFocused: Bool { focused == .memberSearch }

    private var localAllAvailable: [Player] {
        (allAvailable + localGuests).filter { !locallyRemovedIds.contains($0.id) }
    }

    init(
        allAvailable: [Player],
        selectedIDs: Set<Int>,
        nextGuestID: Int,
        supabaseGroupId: UUID? = nil,
        onCancel: @escaping () -> Void,
        onDone: @escaping (ManageMembersResult) -> Void
    ) {
        self.allAvailable = allAvailable
        self.initialSelectedIDs = selectedIDs
        self.initialNextGuestID = nextGuestID
        self.supabaseGroupId = supabaseGroupId
        self.onCancel = onCancel
        self.onDone = onDone
        _selectedIDs = State(initialValue: selectedIDs)
        _nextGuestID = State(initialValue: nextGuestID)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") { onCancel() }
                        .font(.system(size: 16))
                        .foregroundColor(Color.deepNavy)

                    Spacer()

                    Text("Manage Members")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.deepNavy)

                    Spacer()

                    Button("Done") {
                        onDone(ManageMembersResult(
                            selectedIDs: selectedIDs,
                            newGuests: localGuests,
                            nextGuestID: nextGuestID,
                            removedPlayerIds: locallyRemovedIds
                        ))
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.deepNavy)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Add/Invite section
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add/Invite")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color.deepNavy)
                                .frame(height: 32, alignment: .leading)

                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hexString: "#C5C5C7"))
                                TextField("Search by name", text: $memberSearchText)
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.textPrimary)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .focused($focused, equals: .memberSearch)
                                    .onChange(of: memberSearchText) {
                                        debounceOnlineSearch(memberSearchText)
                                    }

                                if !memberSearchText.isEmpty {
                                    Button {
                                        memberSearchText = ""
                                        onlineSearchResults = []
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Color.textDisabled)
                                    }
                                    .accessibilityLabel("Clear search")
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(focused == .memberSearch ? Color(hexString: "#333333") : Color.borderLight, lineWidth: focused == .memberSearch ? 1.5 : 1))
                            .animation(.easeOut(duration: 0.15), value: focused)
                        }
                        .padding(.bottom, 9)

                        // Online search results + inline SMS invite
                        if !memberSearchText.isEmpty {
                            VStack(spacing: 8) {
                                if isSearchingOnline {
                                    HStack(spacing: 8) {
                                        ProgressView().scaleEffect(0.8)
                                        Text("Searching...")
                                            .font(.carry.captionLG)
                                            .foregroundColor(Color.textDisabled)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                } else {
                                    // Carry user results
                                    ForEach(onlineSearchResults, id: \.id) { profile in
                                        onlineSearchResultRow(profile)
                                    }

                                    // Inline SMS invite — same pattern as ScorerAssignmentView
                                    if memberSearchText.count >= 2 && !isSearchingOnline {
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text("Send Invite to \"\(memberSearchText)\"")
                                                .font(.carry.bodySMSemibold)
                                                .foregroundColor(Color.textTertiary)

                                            HStack(spacing: 10) {
                                                Image(systemName: "iphone")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(Color.textDisabled)

                                                TextField("Enter Phone Number", text: $invitePhone)
                                                    .font(.carry.bodyLG)
                                                    .foregroundColor(Color.textPrimary)
                                                    .keyboardType(.phonePad)
                                                    .focused($focused, equals: .invitePhone)
                                                    .onChange(of: invitePhone) { _, newValue in
                                                        let digits = newValue.filter { $0.isNumber }
                                                        if digits.count > 10 {
                                                            invitePhone = String(digits.prefix(10))
                                                        }
                                                    }

                                                let digits = invitePhone.filter { $0.isNumber }
                                                Button {
                                                    sendInvite()
                                                    memberSearchText = ""
                                                    invitePhone = ""
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
                            }
                            .padding(.bottom, 9)
                        }

                        // Green hint banner (dismissible)
                        if showMembersTip {
                            VStack(spacing: 0) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("Tap on players in the All Members section to add/remove them from playing in today's round.")
                                        .font(.carry.bodySM)
                                        .foregroundColor(Color.successGreen)
                                        .lineSpacing(2)
                                    Spacer()
                                    Button {
                                        withAnimation { showMembersTip = false }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .foregroundColor(Color.successGreen)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Dismiss tip")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.concludedGreen)
                            )
                            .padding(.bottom, 9)
                        }

                        // Playing members
                        let playingMembers = localAllAvailable.filter { selectedIDs.contains($0.id) && !$0.isPendingInvite && !$0.isPendingAccept }

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Playing")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color.deepNavy)
                                .frame(height: 32, alignment: .leading)
                            Text("\(playingMembers.count) playing in upcoming game")
                                .font(.system(size: 14))
                                .foregroundColor(Color.textDark)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 5)

                        Group {
                            if playingMembers.isEmpty {
                                Text("Select players from All Members below")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.textDisabled)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            } else {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 20) {
                                    ForEach(playingMembers) { player in
                                        Button {
                                            _ = withAnimation(.easeOut(duration: 0.15)) {
                                                selectedIDs.remove(player.id)
                                            }
                                        } label: {
                                            VStack(spacing: 7) {
                                                ZStack {
                                                    PlayerAvatar(player: player, size: 50)
                                                    VStack {
                                                        Spacer()
                                                        HStack {
                                                            Spacer()
                                                            ZStack {
                                                                Circle().fill(Color(hexString: "#D4F5DC"))
                                                                Image(systemName: "checkmark")
                                                                    .font(.system(size: 12, weight: .bold))
                                                                    .foregroundColor(Color.textPrimary)
                                                            }
                                                            .frame(width: 26, height: 26)
                                                            .offset(x: 6)
                                                        }
                                                    }
                                                }
                                                .frame(width: 50, height: 50)

                                                Text(player.shortName)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(Color.deepNavy)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 79)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(.bottom, 16)

                        Rectangle().fill(Color(hexString: "#EBEBEB")).frame(height: 1).padding(.bottom, 8)

                        // All Members
                        let confirmedMembers = localAllAvailable.filter { !$0.isPendingInvite && !$0.isPendingAccept }
                        let filteredConfirmed: [Player] = {
                            let trimmed = memberSearchText.trimmingCharacters(in: .whitespaces).lowercased()
                            if trimmed.isEmpty { return confirmedMembers }
                            return confirmedMembers.filter { $0.name.lowercased().contains(trimmed) }
                        }()

                        VStack(alignment: .leading, spacing: 0) {
                            Text("All Members")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color.deepNavy)
                                .frame(height: 32, alignment: .leading)
                            Text("\(confirmedMembers.count) members")
                                .font(.system(size: 14))
                                .foregroundColor(Color.textDark)
                        }
                        .padding(.bottom, 5)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 20) {
                            ForEach(filteredConfirmed) { player in
                                let isSelected = selectedIDs.contains(player.id)
                                Button {
                                    if !isSelected {
                                        _ = withAnimation(.easeOut(duration: 0.15)) {
                                            selectedIDs.insert(player.id)
                                        }
                                    }
                                } label: {
                                    VStack(spacing: 7) {
                                        PlayerAvatar(player: player, size: 50)
                                            .opacity(isSelected ? 0.5 : 1)
                                            .frame(width: 50, height: 50)

                                        Text(player.shortName)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Color.deepNavy)
                                            .opacity(isSelected ? 0.5 : 1)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 79)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.45)
                                        .onEnded { _ in requestRemoval(of: player) }
                                )
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                        // Pending
                        let pendingMembers = localAllAvailable.filter { $0.isPendingInvite || $0.isPendingAccept }
                        let filteredPending: [Player] = {
                            let trimmed = memberSearchText.trimmingCharacters(in: .whitespaces).lowercased()
                            if trimmed.isEmpty { return pendingMembers }
                            return pendingMembers.filter {
                                $0.name.lowercased().contains(trimmed) ||
                                ($0.phoneNumber ?? "").contains(trimmed)
                            }
                        }()

                        if !filteredPending.isEmpty {
                            Rectangle().fill(Color(hexString: "#EBEBEB")).frame(height: 1).padding(.bottom, 8)

                            VStack(alignment: .leading, spacing: 0) {
                                Text("Pending")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color.deepNavy)
                                    .frame(height: 32, alignment: .leading)
                                Text("Invited \u{00B7} waiting to join")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.textDark)
                            }
                            .padding(.bottom, 5)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 20) {
                                ForEach(filteredPending) { player in
                                    VStack(spacing: 7) {
                                        ZStack {
                                            if player.isPendingInvite {
                                                ZStack {
                                                    Circle().fill(Color.pendingBg)
                                                    Circle().strokeBorder(Color.pendingBorder, lineWidth: 1.5)
                                                    Image(systemName: "iphone")
                                                        .font(.system(size: 20, weight: .medium))
                                                        .foregroundColor(Color.pendingFill)
                                                }
                                                .frame(width: 50, height: 50)
                                            } else {
                                                PlayerAvatar(player: player, size: 50)
                                            }
                                        }
                                        .frame(width: 50, height: 50)

                                        Text(player.isPendingInvite ? formatPhoneDisplay(player.phoneNumber) : player.shortName)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Color.deepNavy.opacity(0.7))
                                            .lineLimit(1)
                                    }
                                    .frame(width: 79)
                                    .contentShape(Rectangle())
                                    .onLongPressGesture(minimumDuration: 0.45) {
                                        requestRemoval(of: player)
                                    }
                                }
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                focused = nil
            }

        }
        .alert(
            "Remove \(memberToRemove?.name ?? "member")?",
            isPresented: Binding(
                get: { memberToRemove != nil },
                set: { if !$0 { memberToRemove = nil } }
            ),
            presenting: memberToRemove
        ) { player in
            Button("Remove", role: .destructive) { confirmRemoval(of: player) }
            Button("Cancel", role: .cancel) { memberToRemove = nil }
        } message: { player in
            Text("They'll be removed from this Skins Group. You can re-invite them any time.")
        }
    }

    // MARK: - Long-press Remove

    /// Open the iOS-native confirm alert. Scoped to players with a real
    /// profile — phone-only pending invites (no `profileId`) use a
    /// different server row keyed by `invited_phone` that `removeMember`
    /// can't match, so long-press is a silent no-op for those until a
    /// phone-specific removal helper is added.
    private func requestRemoval(of player: Player) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard player.profileId != nil else { return }
        memberToRemove = player
    }

    /// Hard-delete the member server-side, then hide them locally so the
    /// tile disappears without waiting for the next refresh. The Done
    /// callback carries the removed local IDs back to the parent so its
    /// own in-memory group state stays in sync.
    private func confirmRemoval(of player: Player) {
        memberToRemove = nil
        guard let groupId = supabaseGroupId, let profileId = player.profileId else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            locallyRemovedIds.insert(player.id)
            selectedIDs.remove(player.id)
        }

        Task {
            do {
                try await GroupService().removeMember(groupId: groupId, playerId: profileId)
            } catch {
                await MainActor.run {
                    // Rollback if server rejected — re-surface the tile
                    // and let the user retry or investigate.
                    _ = withAnimation(.easeOut(duration: 0.2)) {
                        locallyRemovedIds.remove(player.id)
                    }
                    ToastManager.shared.error("Couldn't remove \(player.name). Try again.")
                }
            }
        }
    }

    // Invite overlay removed — SMS invite is now inline below search results

    // MARK: - Online Search

    private func debounceOnlineSearch(_ query: String) {
        onlineSearchTask?.cancel()
        guard query.count >= 2 else {
            onlineSearchResults = []
            isSearchingOnline = false
            return
        }
        isSearchingOnline = true
        onlineSearchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let offlineResults = PlayerSearchService.shared.searchPlayersOffline(query: query)
            do {
                let results = try await withThrowingTaskGroup(of: [ProfileDTO].self) { group in
                    group.addTask { try await PlayerSearchService.shared.searchPlayers(query: query) }
                    group.addTask { try await Task.sleep(nanoseconds: 3_000_000_000); throw CancellationError() }
                    let first = try await group.next() ?? []
                    group.cancelAll()
                    return first
                }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    onlineSearchResults = results.isEmpty ? offlineResults : results
                    isSearchingOnline = false
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    onlineSearchResults = offlineResults
                    isSearchingOnline = false
                }
            }
        }
    }

    private func onlineSearchResultRow(_ profile: ProfileDTO) -> some View {
        let isAlreadyAdded = localAllAvailable.contains { $0.profileId == profile.id }
        return Button {
            guard !isAlreadyAdded else { return }
            var player = Player(from: profile)
            player.isPendingAccept = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                localGuests.append(player)
            }
            memberSearchText = ""
            onlineSearchResults = []
        } label: {
            HStack(spacing: 12) {
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
                if isAlreadyAdded {
                    Text("Pending")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.pendingFill)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.pendingBg)
                                .overlay(Capsule().strokeBorder(Color.pendingBorder, lineWidth: 1))
                        )
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 14).fill(isAlreadyAdded ? Color.bgSecondary : .white))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyAdded)
    }

    // MARK: - Send Invite

    private func sendInvite() {
        let digits = invitePhone.filter { $0.isNumber }
        guard digits.count >= 10 else { return }
        let guestColors = ["#E67E22", "#9B59B6", "#1ABC9C", "#C0392B", "#2980B9", "#27AE60"]
        let colorIdx = (nextGuestID - 100) % guestColors.count
        let invited = Player(
            id: nextGuestID, name: "Invited", initials: "\u{2709}\u{FE0F}",
            color: guestColors[colorIdx], handicap: 0, avatar: "\u{2709}\u{FE0F}",
            group: 1, ghinNumber: nil, venmoUsername: nil,
            phoneNumber: digits, isPendingInvite: true
        )
        localGuests.append(invited)
        nextGuestID += 1
        withAnimation { inviteSent = true }

        // Create Supabase invite record + send SMS with deep link
        if let groupId = supabaseGroupId {
            Task {
                guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else { return }
                let groupService = GroupService()
                do {
                    try await groupService.inviteMemberByPhone(groupId: groupId, phone: digits, invitedBy: userId)
                    // Open native SMS with deep link
                    let encodedLink = "https://carryapp.site/invite?group=\(groupId.uuidString)"
                    if let smsURL = URL(string: "sms:\(digits)&body=Join%20my%20skins%20game%20on%20Carry!%20\(encodedLink)") {
                        await MainActor.run { UIApplication.shared.open(smsURL) }
                    }
                } catch {
                    #if DEBUG
                    print("[Carry] Failed to create SMS invite record: \(error)")
                    #endif
                    // Still open SMS even if Supabase fails
                    if let smsURL = URL(string: "sms:\(digits)&body=Join%20my%20skins%20game%20on%20Carry!%20https%3A%2F%2Fcarryapp.site") {
                        await MainActor.run { UIApplication.shared.open(smsURL) }
                    }
                }
            }
        } else {
            // No group ID — fallback to static link
            if let smsURL = URL(string: "sms:\(digits)&body=Join%20my%20skins%20game%20on%20Carry!%20https%3A%2F%2Fcarryapp.site") {
                UIApplication.shared.open(smsURL)
            }
        }

        #if DEBUG
        print("[Carry] Invite SMS sent to \(formatPhoneDisplay(digits))")
        #endif
    }

    private func formatPhoneDisplay(_ phone: String?) -> String {
        guard let phone = phone else { return "Invited" }
        let digits = phone.filter { $0.isNumber }
        if digits.count == 10 {
            let area = digits.prefix(3)
            let mid = digits.dropFirst(3).prefix(3)
            let last = digits.suffix(4)
            return "(\(area)) \(mid)-\(last)"
        } else if digits.count == 11 && digits.first == "1" {
            let area = digits.dropFirst(1).prefix(3)
            let mid = digits.dropFirst(4).prefix(3)
            let last = digits.suffix(4)
            return "(\(area)) \(mid)-\(last)"
        }
        return phone
    }
}
