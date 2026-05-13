import SwiftUI

// MARK: - Manage Members Sheet (extracted for performance — no @Binding to parent)

struct ManageMembersSheet: View {
    @EnvironmentObject var authService: AuthService
    let allAvailable: [Player]
    let initialSelectedIDs: Set<Int>
    let initialNextGuestID: Int
    var supabaseGroupId: UUID? = nil
    /// Async refresh hook into the parent's `refreshGroupData()`. Fires
    /// on sheet open (`.task`) and on pull-to-refresh inside the sheet.
    /// Without this, members who flipped to `active` after the sheet
    /// opened (e.g., an invitee accepted while the creator was looking
    /// at this sheet) stayed visible as Pending until force-quit —
    /// SwiftUI doesn't reliably propagate a parent `[Player]` change into
    /// an already-presented sheet's `let` parameter.
    let onRefresh: (() async -> Void)?
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
    /// In-flight `removeMember` server DELETE Tasks. Awaited on Done so
    /// the parent's subsequent `inviteMember` calls don't race against
    /// pending DELETEs. Without this, removing then re-inviting a member
    /// in the same sheet session silently no-ops the invite (server's
    /// existing 'active' row is still there when inviteMember runs;
    /// inviteMember correctly skips, no INSERT, no push).
    @State private var inFlightRemovalTasks: [Task<Void, Never>] = []
    /// Set true while Done is waiting on `inFlightRemovalTasks` to
    /// finish so the button can show a brief progress state instead of
    /// appearing frozen.
    @State private var isFinalizing: Bool = false

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
        onRefresh: (() async -> Void)? = nil,
        onCancel: @escaping () -> Void,
        onDone: @escaping (ManageMembersResult) -> Void
    ) {
        self.allAvailable = allAvailable
        self.initialSelectedIDs = selectedIDs
        self.initialNextGuestID = nextGuestID
        self.supabaseGroupId = supabaseGroupId
        self.onRefresh = onRefresh
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

                    Button {
                        // Await any in-flight removeMember DELETEs before
                        // returning. The parent's onDone closure will issue
                        // inviteMember calls for `newGuests`; without this
                        // await, a removed-then-re-added member's invite
                        // races the DELETE and silently no-ops on the
                        // existing 'active' row.
                        guard !isFinalizing else { return }
                        isFinalizing = true
                        Task {
                            for task in inFlightRemovalTasks {
                                _ = await task.value
                            }
                            await MainActor.run {
                                inFlightRemovalTasks.removeAll()
                                isFinalizing = false
                                onDone(ManageMembersResult(
                                    selectedIDs: selectedIDs,
                                    newGuests: localGuests,
                                    nextGuestID: nextGuestID,
                                    removedPlayerIds: locallyRemovedIds
                                ))
                            }
                        }
                    } label: {
                        if isFinalizing {
                            ProgressView()
                                .scaleEffect(0.85)
                        } else {
                            Text("Done")
                        }
                    }
                    .disabled(isFinalizing)
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
                                    // Carry user results — filter out
                                    // anyone already in this group (any
                                    // status). They appear in All
                                    // Members above; surfacing them
                                    // here as disabled rows is clutter.
                                    let existingProfileIds = Set(localAllAvailable.compactMap(\.profileId))
                                    let filteredResults = onlineSearchResults.filter { !existingProfileIds.contains($0.id) }
                                    ForEach(filteredResults, id: \.id) { profile in
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
                                                    // Match the onboarding/profile guard: strip non-digits,
                                                    // drop a leading US country-code "1" so iOS contact
                                                    // autofill ("+1 (415) 697-9011" / "1415...") lands as
                                                    // a clean 10-digit number rather than chopping the tail.
                                                    .onChange(of: invitePhone) {
                                                        let digits = invitePhone.filter(\.isNumber)
                                                        let normalized = (digits.count == 11 && digits.hasPrefix("1"))
                                                            ? String(digits.dropFirst())
                                                            : digits
                                                        let capped = String(normalized.prefix(10))
                                                        if capped != invitePhone { invitePhone = capped }
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
                                    Text("Tap on players in the All Members section to add/remove them from playing in today's round. Long press to delete member permanently.")
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

                                        // Prefer the typed `invitee_name` (carried through
                                        // as Player.name from loadSingleGroup) when it
                                        // exists — falls back to the formatted phone when
                                        // the inviter didn't type a name (or for legacy
                                        // pre-invitee_name rows where name is the raw
                                        // phone digits). Detect "is just digits" by
                                        // stripping non-digit chars and comparing length.
                                        Text(pendingChipLabel(for: player))
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
            .refreshable {
                await onRefresh?()
            }
            .task {
                await onRefresh?()
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

    /// Open the iOS-native confirm alert. Accepts both:
    ///   - Confirmed Carry members (have `profileId`) → server delete by
    ///     (group_id, player_id) via `removeMember`
    ///   - Pending SMS-invite rows (no `profileId` but have
    ///     `inviteMemberId` = the row's group_members.id, set by
    ///     loadSingleGroup and ManageMembersSheet.sendInvite) → server
    ///     hard-delete by row id
    /// Silent no-op when neither identifier is available (defensive)
    /// OR when the target is the logged-in user themselves — Leave/Delete
    /// Group is the canonical self-removal path; long-press in Manage
    /// Members shouldn't let the user delete themselves and leave the
    /// group in a creator-less state.
    private func requestRemoval(of player: Player) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard player.profileId != nil || player.inviteMemberId != nil else { return }
        if let selfProfileId = authService.currentUser?.id, player.profileId == selfProfileId {
            ToastManager.shared.error("You can't remove yourself — use Leave/Delete Group.")
            return
        }
        memberToRemove = player
    }

    /// Hard-delete the member server-side, then hide them locally so the
    /// tile disappears without waiting for the next refresh. The Task is
    /// tracked in `inFlightRemovalTasks` so Done can await it before
    /// returning — preventing a race where re-inviting the same player
    /// in the same sheet session beats the DELETE to the server and
    /// silently no-ops.
    private func confirmRemoval(of player: Player) {
        memberToRemove = nil
        guard let groupId = supabaseGroupId else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            locallyRemovedIds.insert(player.id)
            selectedIDs.remove(player.id)
        }

        let task = Task<Void, Never> {
            do {
                if player.isPendingInvite, let inviteMemberId = player.inviteMemberId {
                    // Phone-invite path — delete by row id. The row's
                    // `player_id` is the inviter's UUID placeholder, so
                    // a (group_id, player_id) delete would either miss
                    // or accidentally hit the inviter's regular row.
                    try await SupabaseManager.shared.client
                        .from("group_members")
                        .delete()
                        .eq("id", value: inviteMemberId.uuidString)
                        .execute()
                } else if let profileId = player.profileId {
                    try await GroupService().removeMember(groupId: groupId, playerId: profileId)
                }
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
        inFlightRemovalTasks.append(task)
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
        let existingMember = localAllAvailable.first { $0.profileId == profile.id }
        let isAlreadyAdded = existingMember != nil
        // Pill state derived from the actual member's local state so a
        // confirmed/active member doesn't show "Pending" (which was the
        // catch-all for "already added" — confusing when the searcher
        // is searching themselves and is fully joined).
        let pillLabel: String? = {
            guard let member = existingMember else { return nil }
            if member.isPendingAccept { return "Pending" }
            if member.isPendingInvite { return "Invited" }
            return "Added"
        }()
        return Button {
            guard !isAlreadyAdded else { return }
            // Carry users go in as active immediately (no accept step).
            // Matches the parent's onDone in GroupManagerView which now
            // persists with status="active" via inviteMember.
            let player = Player(from: profile)
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
                if let label = pillLabel {
                    Text(label)
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
        // Self-invite block — match ScorerAssignmentView's pattern.
        // Without this, an inviter typing their own phone here would
        // create a phone-invite row that the reverse-reconcile trigger
        // would immediately collapse into their own profile → silent
        // double-add into group_members with the inviter as both
        // creator and pending-invite.
        if let selfDigits = authService.currentUser?.phone?.filter({ $0.isNumber }),
           selfDigits.suffix(10) == digits.suffix(10),
           !selfDigits.isEmpty {
            ToastManager.shared.error("You can't invite yourself — you're already a member.")
            return
        }
        let guestColors = ["#E67E22", "#9B59B6", "#1ABC9C", "#C0392B", "#2980B9", "#27AE60"]
        let colorIdx = (nextGuestID - 100) % guestColors.count
        // Capture the typed name from the search field (the "Send
        // Invite to '<name>'" label). Falls back to the formatted
        // phone if the user somehow opened the SMS path without
        // typing a name first (shouldn't happen — gate is
        // `memberSearchText.count >= 2` — but defensive).
        let typedName = memberSearchText.trimmingCharacters(in: .whitespaces)
        let displayName = typedName.isEmpty ? digits : typedName
        // Mint a stable UUID for this invite. Used as the explicit
        // group_members.id via reservePhoneInvite so the row's id is
        // known client-side from the start (matches what
        // loadSingleGroup will compute on refresh).
        let inviteId = UUID()
        let invited = Player(
            id: nextGuestID, name: displayName, initials: "\u{2709}\u{FE0F}",
            color: guestColors[colorIdx], handicap: 0, avatar: "\u{2709}\u{FE0F}",
            group: 1, ghinNumber: nil, venmoUsername: nil,
            phoneNumber: digits, isPendingInvite: true,
            inviteMemberId: inviteId
        )
        localGuests.append(invited)
        nextGuestID += 1
        withAnimation { inviteSent = true }

        // Create Supabase invite record + send SMS with deep link.
        // Switched from legacy inviteMemberByPhone to reservePhoneInvite
        // so the typed name lands on the server's invitee_name column —
        // survives refresh + cross-device, so the Pending chip stays
        // readable as "Daniel" / "(415) 697-9011" rather than reverting
        // to the placeholder.
        if let groupId = supabaseGroupId {
            Task {
                guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else { return }
                let groupService = GroupService()
                do {
                    _ = try await groupService.reservePhoneInvite(
                        id: inviteId,
                        groupId: groupId,
                        phone: digits,
                        invitedBy: userId,
                        groupNum: 1,
                        inviteeName: typedName.isEmpty ? nil : typedName
                    )
                    // Open native SMS with deep link. The body's
                    // own `?group=` query was being chewed up by the
                    // sms URL parser because `.urlQueryAllowed`
                    // permits `?`, `&`, `=` — the body terminated
                    // early and Messages dropped everything after
                    // `/invite`. Build a stricter set: urlQueryAllowed
                    // minus the four characters that segment a URL
                    // query string. Now the `?`, `&`, `=` inside the
                    // body get percent-escaped as `%3F`, `%26`, `%3D`
                    // and the full body roundtrips through Messages.
                    let body = "Join my skins game on Carry! https://carryapp.site/invite?group=\(groupId.uuidString)"
                    var allowed = CharacterSet.urlQueryAllowed
                    allowed.remove(charactersIn: "?&=#")
                    let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                    if let smsURL = URL(string: "sms:\(digits)&body=\(encoded)") {
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

    /// Label for the pending-invites chip grid. Prefers the inviter-
    /// typed name (carried through Player.name from
    /// loadSingleGroup's invitee_name read) so users see "Dan" rather
    /// than "(333) 333-..." truncated. Caps at 8 chars + "…" so long
    /// names ("Christopher") don't overflow the 79pt chip width.
    ///
    /// Fallback chain:
    /// 1. Typed name (truncated to 8 chars + … if longer)
    /// 2. Formatted phone (legacy rows that predate invitee_name)
    /// 3. Literal "Invited" if neither is available (very rare —
    ///    only possible if Player.name + phoneNumber are both empty,
    ///    which shouldn't happen for pending invites in practice)
    private func pendingChipLabel(for player: Player) -> String {
        if !player.isPendingInvite { return player.shortName }
        let trimmed = player.name.trimmingCharacters(in: .whitespaces)
        let digitsOnly = trimmed.filter(\.isNumber).count == trimmed.filter({ !$0.isWhitespace }).count
        if !trimmed.isEmpty, !digitsOnly {
            // 8 chars + ellipsis when longer. shortName ("First L.")
            // handles multi-word names; single-word names go through
            // unchanged before the 8-char clip.
            let base = player.shortName
            if base.count > 8 {
                return String(base.prefix(8)) + "…"
            }
            return base
        }
        return formatPhoneDisplay(player.phoneNumber)
    }
}
