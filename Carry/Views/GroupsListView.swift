import SwiftUI

struct GroupsListView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showCreateGroup = false
    @State private var groups: [SavedGroup] = SavedGroup.demo
    @State private var activeGroup: SavedGroup? = nil

    var body: some View {
        ZStack {
            Color(hex: "#F0F0F0").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Skin Games")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color(hex: "#1A1A1A"))

                    Spacer()

                    // Create new group button
                    Button {
                        showCreateGroup = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#C4A450").opacity(0.15))
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(hex: "#C4A450"))
                        }
                        .frame(width: 40, height: 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)

                ScrollView {
                    VStack(spacing: 12) {
                        if groups.isEmpty {
                            emptyState
                        } else {
                            ForEach(groups) { group in
                                groupCard(group)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()
            }
        }
        .sheet(isPresented: $showCreateGroup) {
            CreateGroupSheet { newGroup in
                groups.append(newGroup)
                showCreateGroup = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $activeGroup) { group in
            RoundCoordinatorView(
                initialMembers: group.members,
                groupName: group.name,
                currentUserId: 1,
                onExit: { activeGroup = nil }
            )
        }
    }

    // MARK: - Group Card

    private func groupCard(_ group: SavedGroup) -> some View {
        Button {
            activeGroup = group
        } label: {
            HStack(spacing: 14) {
                // Avatar stack
                avatarStack(group: group)

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    HStack(spacing: 6) {
                        Text("\(group.members.count) members")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#999999"))
                        if let lastPlayed = group.lastPlayed {
                            Text("\u{00B7}")
                                .foregroundColor(Color(hex: "#CCCCCC"))
                            Text("Last played: \(lastPlayed)")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#999999"))
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "#CCCCCC"))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
            )
        }
        .buttonStyle(.plain)
    }

    private func avatarStack(group: SavedGroup) -> some View {
        let display = Array(group.members.prefix(4))
        return ZStack {
            ForEach(Array(display.enumerated()), id: \.offset) { idx, player in
                ZStack {
                    Circle()
                        .fill(Color(hex: player.color).opacity(0.09))
                    Circle()
                        .strokeBorder(Color(hex: player.color).opacity(0.25), lineWidth: 1.5)
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                    Text(player.avatar)
                        .font(.system(size: 14))
                }
                .frame(width: 30, height: 30)
                .offset(x: CGFloat(idx) * 14)
            }
        }
        .frame(width: CGFloat(min(display.count, 4) - 1) * 14 + 30, alignment: .leading)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3")
                .font(.system(size: 32))
                .foregroundColor(Color(hex: "#CCCCCC"))

            Text("No skin games yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(hex: "#999999"))

            Text("Create a skin game to track skins with your crew.")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#CCCCCC"))
                .multilineTextAlignment(.center)

            Button {
                showCreateGroup = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("New Skin Game")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: "#1A1A1A"))
                )
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 60)
    }
}

// MARK: - Saved Group Model

struct SavedGroup: Identifiable {
    let id: UUID
    let name: String
    let members: [Player]
    let lastPlayed: String?

    static let demo: [SavedGroup] = [
        SavedGroup(
            id: UUID(),
            name: "Friday Meetings",
            members: Player.allPlayers,
            lastPlayed: "Mar 1"
        ),
    ]
}

// MARK: - Create Group Sheet

struct CreateGroupSheet: View {
    let onCreate: (SavedGroup) -> Void

    @State private var groupName = ""
    @State private var selectedIDs: Set<Int> = []
    @State private var showAddSheet = false
    @State private var showGuestEntry = false
    @State private var guestName = ""
    @State private var guestHandicap = ""
    @State private var guests: [Player] = []
    @State private var nextGuestID = 100
    @State private var showInviteEntry = false
    @State private var inviteEmail = ""
    @State private var inviteName = ""
    @State private var inviteChecking = false
    @State private var inviteResult: InviteResult?

    private var allPlayers: [Player] { Player.allPlayers + guests }

    enum InviteResult {
        case found(ProfileDTO)
        case notFound
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("New Skins Game")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))
                .padding(.top, 28)
                .padding(.bottom, 24)

            // Group name field
            VStack(alignment: .leading, spacing: 6) {
                Text("GROUP NAME")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(Color(hex: "#BBBBBB"))
                    .padding(.leading, 4)

                TextField("e.g. Friday Meetings", text: $groupName)
                    .font(.system(size: 16))
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(hex: "#E0E0E0"), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // Members section
            VStack(alignment: .leading, spacing: 6) {
                Text("MEMBERS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(Color(hex: "#BBBBBB"))
                    .padding(.leading, 4)

                Text("\(selectedIDs.count) selected")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#999999"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Player grid
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    // Add player chip (first item)
                    addPlayerChip

                    ForEach(allPlayers) { player in
                        memberChip(player)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // Create button
            Button {
                let members = allPlayers.filter { selectedIDs.contains($0.id) }
                let group = SavedGroup(
                    id: UUID(),
                    name: groupName.trimmingCharacters(in: .whitespaces),
                    members: members,
                    lastPlayed: nil
                )
                onCreate(group)
            } label: {
                Text("Create Skins Game")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canCreate ? Color(hex: "#1A1A1A") : Color(hex: "#CCCCCC"))
                    )
            }
            .disabled(!canCreate)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .background(Color(hex: "#F0F0F0"))
        .sheet(isPresented: $showAddSheet) {
            addPlayerSheetView
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGuestEntry) {
            guestEntrySheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showInviteEntry) {
            inviteMemberSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty && selectedIDs.count >= 2
    }

    // MARK: - Add Player Chip

    private var addPlayerChip: some View {
        Button {
            showAddSheet = true
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#1A1A1A").opacity(0.06))
                    Circle()
                        .strokeBorder(Color(hex: "#1A1A1A").opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                }
                .frame(width: 52, height: 52)

                Text("Add")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#999999"))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Player Sheet

    private var addPlayerSheetView: some View {
        VStack(spacing: 0) {
            Text("Add Player")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))
                .padding(.top, 24)
                .padding(.bottom, 20)

            // Guest option
            Button {
                showAddSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showGuestEntry = true
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#F0F0F0"))
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Guest")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                        Text("Temporary player for this group")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#999999"))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#CCCCCC"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color(hex: "#F0F0F0"))
                .frame(height: 1)
                .padding(.leading, 74)

            // Invite existing member option
            Button {
                showAddSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    inviteEmail = ""
                    inviteName = ""
                    inviteResult = nil
                    showInviteEntry = true
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#F0F0F0"))
                        Image(systemName: "person.2.badge.plus")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invite Member")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                        Text("Look up or invite by email")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#999999"))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#CCCCCC"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Guest Entry Sheet

    private var guestEntrySheet: some View {
        VStack(spacing: 0) {
            Text("Add Guest")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))
                .padding(.top, 24)
                .padding(.bottom, 24)

            VStack(spacing: 16) {
                // Name field
                VStack(alignment: .leading, spacing: 6) {
                    Text("NAME")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(Color(hex: "#BBBBBB"))
                        .padding(.leading, 4)

                    TextField("Guest name", text: $guestName)
                        .font(.system(size: 16))
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(hex: "#E0E0E0"), lineWidth: 1)
                        )
                }

                // Handicap field
                VStack(alignment: .leading, spacing: 6) {
                    Text("HANDICAP")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(Color(hex: "#BBBBBB"))
                        .padding(.leading, 4)

                    TextField("e.g. 12.4", text: $guestHandicap)
                        .font(.system(size: 16))
                        .keyboardType(.decimalPad)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(hex: "#E0E0E0"), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Add button
            Button {
                addGuest()
            } label: {
                Text("Add Guest")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(!guestName.trimmingCharacters(in: .whitespaces).isEmpty
                                  ? Color(hex: "#1A1A1A")
                                  : Color(hex: "#CCCCCC"))
                    )
            }
            .disabled(guestName.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .background(Color(hex: "#F0F0F0"))
    }

    // MARK: - Add Guest Logic

    private func addGuest() {
        let trimmedName = guestName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let hcp = Double(guestHandicap) ?? 0.0
        let guestColors = ["#E67E22", "#9B59B6", "#1ABC9C", "#C0392B", "#2980B9", "#27AE60"]
        let guestAvatars = ["👤", "🎩", "🧢", "🕶️", "⛳", "🏌️"]
        let colorIdx = (nextGuestID - 100) % guestColors.count
        let avatarIdx = (nextGuestID - 100) % guestAvatars.count

        let guest = Player(
            id: nextGuestID,
            name: trimmedName,
            initials: String(trimmedName.prefix(2)).uppercased(),
            color: guestColors[colorIdx],
            handicap: hcp,
            avatar: guestAvatars[avatarIdx],
            group: 1,
            ghinNumber: nil
        )

        guests.append(guest)
        selectedIDs.insert(guest.id)
        nextGuestID += 1

        // Reset form
        guestName = ""
        guestHandicap = ""
        showGuestEntry = false
    }

    // MARK: - Invite Member Sheet

    private var inviteMemberSheet: some View {
        VStack(spacing: 0) {
            Text("Invite Member")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))
                .padding(.top, 24)
                .padding(.bottom, 24)

            VStack(spacing: 16) {
                // Email field
                VStack(alignment: .leading, spacing: 6) {
                    Text("EMAIL")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(Color(hex: "#BBBBBB"))
                        .padding(.leading, 4)

                    HStack(spacing: 10) {
                        TextField("email@example.com", text: $inviteEmail)
                            .font(.system(size: 16))
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color(hex: "#E0E0E0"), lineWidth: 1)
                            )
                            .onChange(of: inviteEmail) { _ in
                                // Reset result when email changes
                                inviteResult = nil
                            }

                        // Look up button
                        Button {
                            lookupEmail()
                        } label: {
                            if inviteChecking {
                                ProgressView()
                                    .frame(width: 48, height: 48)
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(inviteEmail.contains("@") ? Color(hex: "#1A1A1A") : Color(hex: "#CCCCCC"))
                                    )
                            }
                        }
                        .disabled(!inviteEmail.contains("@") || inviteChecking)
                    }
                }

                // Result section
                if let result = inviteResult {
                    switch result {
                    case .found(let profile):
                        // Found existing user
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: profile.color).opacity(0.09))
                                Circle()
                                    .strokeBorder(Color(hex: profile.color).opacity(0.3), lineWidth: 1.5)
                                Text(profile.avatar)
                                    .font(.system(size: 20))
                            }
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Color(hex: "#1A1A1A"))
                                Text("HCP \(String(format: "%.1f", profile.handicap))")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "#999999"))
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color(hex: "#27AE60"))
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "#27AE60").opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(hex: "#27AE60").opacity(0.2), lineWidth: 1)
                        )

                    case .notFound:
                        // Not found — show name field for invite
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "envelope.badge.person.crop")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "#C4A450"))
                                Text("Not on Carry yet — send an invite!")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(hex: "#999999"))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("NAME")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(1.5)
                                    .foregroundColor(Color(hex: "#BBBBBB"))
                                    .padding(.leading, 4)

                                TextField("Their name", text: $inviteName)
                                    .font(.system(size: 16))
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.white)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(Color(hex: "#E0E0E0"), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Action button
            if let result = inviteResult {
                Button {
                    switch result {
                    case .found(let profile):
                        addFoundMember(profile)
                    case .notFound:
                        sendInvite()
                    }
                } label: {
                    Text(inviteActionLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(inviteActionEnabled ? Color(hex: "#1A1A1A") : Color(hex: "#CCCCCC"))
                        )
                }
                .disabled(!inviteActionEnabled)
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .background(Color(hex: "#F0F0F0"))
    }

    private var inviteActionLabel: String {
        guard let result = inviteResult else { return "" }
        switch result {
        case .found: return "Add to Group"
        case .notFound: return "Send Invite"
        }
    }

    private var inviteActionEnabled: Bool {
        guard let result = inviteResult else { return false }
        switch result {
        case .found: return true
        case .notFound: return !inviteName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func lookupEmail() {
        inviteChecking = true
        inviteResult = nil

        Task {
            // Query Supabase profiles for this email
            // Note: requires 'email' column on profiles table (future migration)
            do {
                let profiles: [ProfileDTO] = try await SupabaseManager.shared.client
                    .from("profiles")
                    .select()
                    .eq("email", value: inviteEmail.trimmingCharacters(in: .whitespaces).lowercased())
                    .execute()
                    .value

                await MainActor.run {
                    if let profile = profiles.first {
                        inviteResult = .found(profile)
                    } else {
                        inviteResult = .notFound
                    }
                    inviteChecking = false
                }
            } catch {
                // If query fails (e.g. column doesn't exist yet), treat as not found
                await MainActor.run {
                    inviteResult = .notFound
                    inviteChecking = false
                }
            }
        }
    }

    private func addFoundMember(_ profile: ProfileDTO) {
        // Create a Player from the found profile and add to group
        let player = Player(
            id: nextGuestID,
            name: profile.displayName,
            initials: profile.initials,
            color: profile.color,
            handicap: profile.handicap,
            avatar: profile.avatar,
            group: 1,
            ghinNumber: profile.ghinNumber
        )

        guests.append(player)
        selectedIDs.insert(player.id)
        nextGuestID += 1
        showInviteEntry = false
    }

    private func sendInvite() {
        let trimmedName = inviteName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // Create a pending invited member
        let inviteColors = ["#3498DB", "#E74C3C", "#2ECC71", "#F39C12", "#9B59B6", "#1ABC9C"]
        let colorIdx = (nextGuestID - 100) % inviteColors.count

        let player = Player(
            id: nextGuestID,
            name: trimmedName,
            initials: String(trimmedName.prefix(2)).uppercased(),
            color: inviteColors[colorIdx],
            handicap: 0,
            avatar: "📩",
            group: 1,
            ghinNumber: nil
        )

        guests.append(player)
        selectedIDs.insert(player.id)
        nextGuestID += 1

        // TODO: Send actual email invite via Supabase Edge Function
        // For now, just add them as a pending member

        showInviteEntry = false
    }

    // MARK: - Member Chip

    private func memberChip(_ player: Player) -> some View {
        let isSelected = selectedIDs.contains(player.id)

        return Button {
            if isSelected {
                selectedIDs.remove(player.id)
            } else {
                selectedIDs.insert(player.id)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color(hex: player.color).opacity(0.09))
                    Circle()
                        .strokeBorder(
                            Color(hex: player.color).opacity(0.3),
                            lineWidth: 1.5
                        )
                    Text(player.avatar)
                        .font(.system(size: 22))

                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "#1A1A1A"))
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 16, height: 16)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(width: 52, height: 52)

                Text(player.truncatedName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
