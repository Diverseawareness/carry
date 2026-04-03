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

    enum Field: Hashable { case memberSearch, invitePhone }
    @FocusState private var focused: Field?
    private var isSearchFocused: Bool { focused == .memberSearch }

    private var localAllAvailable: [Player] {
        allAvailable + localGuests
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
                            nextGuestID: nextGuestID
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

                        // Online search results
                        if !memberSearchText.isEmpty {
                            VStack(spacing: 0) {
                                if isSearchingOnline {
                                    HStack(spacing: 8) {
                                        ProgressView().scaleEffect(0.8)
                                        Text("Searching...")
                                            .font(.system(size: 14))
                                            .foregroundColor(Color.textDisabled)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                } else if onlineSearchResults.isEmpty && memberSearchText.count >= 2 {
                                    VStack(spacing: 4) {
                                        Text("No users found")
                                            .font(.system(size: 14))
                                            .foregroundColor(Color.textDisabled)
                                        Text("Invite them via text message instead")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color.borderLight)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                } else {
                                    ForEach(onlineSearchResults, id: \.id) { profile in
                                        onlineSearchResultRow(profile)
                                    }
                                }
                            }
                            .padding(.bottom, 9)
                        }

                        // Invite a Friend row
                        Button {
                            invitePhone = ""
                            inviteSent = false
                            withAnimation(.easeOut(duration: 0.25)) {
                                showInviteModal = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.bgPrimary)
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 18))
                                        .foregroundColor(Color.textPrimary)
                                }
                                .frame(width: 42, height: 42)

                                VStack(alignment: .leading, spacing: 0) {
                                    Text("Invite via SMS")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(Color.deepNavy)
                                    Text("Send a link to download the app")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color(hexString: "#858589"))
                                }
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color.borderMedium)
                            }
                            .padding(.horizontal, 13.5)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(hexString: "#DDDDE1"), lineWidth: 1)
                        )
                        .padding(.bottom, 9)

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
                            Text("Playing today")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color.deepNavy)
                                .frame(height: 32, alignment: .leading)
                            Text("\(playingMembers.count) players in todays game")
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
                                                    Image(systemName: "message.fill")
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
                                }
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSearchFocused {
                    Button {
                        focused = nil
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 51)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.textPrimary))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.white)
                }
            }
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .allowsHitTesting(!showInviteModal)

            if showInviteModal {
                inviteOverlay.transition(.opacity).zIndex(1)
            }
        }
    }

    // MARK: - Invite Overlay

    private var inviteOverlay: some View {
        let digits = invitePhone.filter { $0.isNumber }
        let canSend = digits.count >= 10

        return ZStack {
            Color.white.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.25)) { showInviteModal = false }
                }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showInviteModal = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.bgPrimary))
                    }
                }
                .padding(.top, 16)
                .padding(.trailing, 16)

                if inviteSent {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle().fill(Color.textPrimary).frame(width: 72, height: 72)
                            Image(systemName: "checkmark")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("Invite Sent!")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color.textPrimary)
                        Text("We texted \(formatPhoneDisplay(digits)) a link to join on Carry.")
                            .font(.system(size: 15))
                            .foregroundColor(Color.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 20)
                    .padding(.bottom, 8)

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            inviteSent = false
                            invitePhone = ""
                            showInviteModal = false
                        }
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.textPrimary))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                } else {
                    Text("Invite Player")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                        .padding(.bottom, 4)

                    Text("They\u{2019}ll get a text with a link to download Carry and join your game.")
                        .font(.system(size: 14))
                        .foregroundColor(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Phone Number")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.textPrimary)
                            .padding(.leading, 4)

                        TextField("(555) 123-4567", text: $invitePhone)
                            .font(.system(size: 16))
                            .focused($focused, equals: .invitePhone)
                            .keyboardType(.phonePad)
                            .onChange(of: invitePhone) {
                                invitePhone = invitePhone.filter { $0.isNumber || $0 == "+" }
                            }
                            .carryInput(focused: focused == .invitePhone, cornerRadius: 10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    Button {
                        sendInvite()
                    } label: {
                        Text("Send Invite")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(canSend ? Color.textPrimary : Color.borderSubtle)
                            )
                    }
                    .disabled(!canSend)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            )
            .padding(.horizontal, 32)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .animation(.easeOut(duration: 0.25), value: inviteSent)
        }
    }

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
                ZStack {
                    Circle().fill(Color.pendingBg)
                    Circle().strokeBorder(Color.pendingBorder, lineWidth: 1.5)
                    Text(profile.initials)
                        .font(.custom("ANDONESI-Regular", size: 17))
                        .foregroundColor(Color.pendingFill)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(profile.firstName) \(profile.lastName)")
                        .font(.system(size: 16))
                        .foregroundColor(Color.textPrimary)
                    let subtitle = [profile.homeClub, profile.handicap != 0 ? String(format: "%.1f", profile.handicap) : nil]
                        .compactMap { $0 }.joined(separator: " \u{00B7} ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(Color.textSecondary)
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
                } else {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18))
                        .foregroundColor(Color.textDisabled)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12).fill(isAlreadyAdded ? Color.bgSecondary : .white))
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
