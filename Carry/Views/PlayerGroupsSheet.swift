import SwiftUI

/// Result returned from PlayerGroupsSheet on Save.
struct PlayerGroupsResult {
    let groups: [[Player]]
    let scorerIDs: [Int]
    let teeTimes: [Date?]
    let startingSides: [String]
    let selectedTees: [String]
    let allMembers: [Player]
    let selectedIDs: Set<Int>
    let nextGuestID: Int
}

/// Extracted Player Groups management sheet — has its own @State so typing
/// doesn't re-render the parent GroupManagerView (4000+ lines).
struct PlayerGroupsSheet: View {
    @EnvironmentObject var storeService: StoreService

    // Initial data — copied into local @State on appear
    let initialGroups: [[Player]]
    let initialScorerIDs: [Int]
    let initialTeeTimes: [Date?]
    let initialStartingSides: [String]
    let initialSelectedTees: [String]
    let initialAllMembers: [Player]
    let initialSelectedIDs: Set<Int>
    let initialNextGuestID: Int

    // Context from parent (read-only)
    let currentUserId: Int
    let supabaseGroupId: UUID?
    let isQuickGame: Bool
    let handicapPercentage: Double
    let currentCourse: SelectedCourse?

    // Callbacks
    let onSave: (PlayerGroupsResult) -> Void
    let onCancel: () -> Void

    // MARK: - Local State (isolated from parent)

    @State private var groups: [[Player]] = []
    @State private var scorerIDs: [Int] = []
    @State private var teeTimes: [Date?] = []
    @State private var startingSides: [String] = []
    @State private var selectedTees: [String] = []
    @State private var allMembers: [Player] = []
    @State private var selectedIDs: Set<Int> = []
    @State private var nextGuestID: Int = 100

    @State private var emptySlotNames: [String: String] = [:]
    @State private var emptySlotHCs: [String: String] = [:]
    @State private var scorerSlots: [ScorerSlot] = []

    /// Fixed-position slot tracking: 3 non-scorer slots per group.
    /// Each slot is either an assigned player ID or nil (empty).
    /// Prevents players from shifting up when a slot is cleared.
    @State private var slotAssignments: [[Int?]] = []

    @State private var showRemoveGroupConfirm = false
    @State private var removeGroupIndex: Int? = nil
    @State private var showPaywall = false

    @State private var showHCPicker = false
    @State private var hcPickerValue: Double = 0
    @State private var hcPickerIsPlus: Bool = false
    @State private var hcPickerCommit: ((Double, Bool) -> Void)? = nil

    // Player name typeahead search
    @State private var playerSearchResults: [ProfileDTO] = []
    @State private var playerSearchTask: Task<Void, Never>?
    @State private var activePlayerSearchSlot: (group: Int, slot: Int)? = nil

    // SMS invite
    @State private var phoneText: String = ""
    @State private var phoneName: String = ""

    /// Tracks which empty slot name field is currently focused (group, slot).
    /// Used to trigger search typeahead on text changes.
    @State private var focusedEmptySlot: (group: Int, slot: Int)? = nil

    @State private var didInit = false

    private let maxGroupSize = 4

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZStack {
                Text("Player Groups")
                    .font(.carry.headline)
                    .foregroundColor(Color.textPrimary)

                HStack {
                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .font(.carry.body)
                            .foregroundColor(Color.textTertiary)
                    }
                    Spacer()
                    Button {
                        // Non-premium creators can open the sheet and see
                        // current state, but Save routes through the paywall
                        // — keeps server-side group data clean.
                        if !storeService.isPremium {
                            showPaywall = true
                            return
                        }
                        if canSave {
                            Task { await saveAndDismiss() }
                        } else if let hint = saveHint {
                            ToastManager.shared.error(hint)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text("Save")
                                .font(.carry.bodySemibold)
                                .foregroundColor(canSave ? Color.textPrimary : Color.textDisabled)
                            if !storeService.isPremium {
                                Image("premium-crown")
                                    .resizable()
                                    .renderingMode(.template)
                                    .scaledToFit()
                                    .frame(width: 11, height: 11)
                                    .foregroundColor(Color.goldAccent)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .background(.white)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Premium banner — surfaces when a non-premium creator
                    // opens the sheet. Tap jumps straight to the paywall.
                    // The groupCards below stay interactive so users can
                    // explore the UI, but Save routes through the paywall.
                    if !storeService.isPremium {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 10) {
                                Image("premium-crown")
                                    .resizable()
                                    .renderingMode(.template)
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                                    .foregroundColor(Color.goldAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Managing groups requires Premium")
                                        .font(.carry.bodySMBold)
                                        .foregroundColor(Color.textPrimary)
                                    Text("Upgrade to save changes")
                                        .font(.carry.caption)
                                        .foregroundColor(Color.textSecondary)
                                }
                                Spacer()
                                Text("Upgrade")
                                    .font(.carry.captionLG)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.goldAccent))
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.bgSecondary)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .accessibilityLabel("Upgrade to Premium to manage groups")
                    }

                    ForEach(Array(groups.enumerated()), id: \.offset) { groupIdx, groupPlayers in
                        groupCard(groupIndex: groupIdx, players: groupPlayers)
                    }

                    if groups.count < 5 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                groups.append([])
                                scorerSlots.append(ScorerSlot())
                                slotAssignments.append([nil, nil, nil])
                                syncTeeTimes()
                                syncScorerIDs()
                            }
                        } label: {
                            Text("+ Add Group")
                                .font(.carry.bodySMBold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color.textPrimary))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .background(.white)
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            focusedEmptySlot = nil
            playerSearchResults = []
            activePlayerSearchSlot = nil
        }
        .carryToastOverlay()
        .sheet(isPresented: $showHCPicker) {
            HandicapPickerSheet(
                handicap: $hcPickerValue,
                isPlus: $hcPickerIsPlus
            )
            .presentationDetents([.height(520)])
            .presentationDragIndicator(.visible)
            .onDisappear {
                hcPickerCommit?(hcPickerValue, hcPickerIsPlus)
                hcPickerCommit = nil
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(trigger: .manageGroup)
                .environmentObject(storeService)
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            groups = initialGroups
            scorerIDs = initialScorerIDs
            teeTimes = initialTeeTimes
            startingSides = initialStartingSides
            selectedTees = initialSelectedTees
            allMembers = initialAllMembers
            selectedIDs = initialSelectedIDs
            nextGuestID = initialNextGuestID

            // Build scorer slots from current state
            scorerSlots = groups.enumerated().map { (gi, group) in
                let sid = gi < scorerIDs.count ? scorerIDs[gi] : 0
                guard let scorer = group.first(where: { $0.id == sid }) else { return ScorerSlot() }
                return ScorerSlot(
                    name: scorer.name,
                    handicap: formatHandicap(scorer.handicap),
                    profileId: scorer.profileId,
                    color: scorer.color,
                    isPendingInvite: scorer.isPendingInvite,
                    phoneNumber: scorer.phoneNumber,
                    avatarUrl: scorer.avatarUrl,
                    homeClub: scorer.homeClub
                )
            }

            // Build fixed-position slot assignments from existing groups
            slotAssignments = groups.enumerated().map { (gi, group) in
                let scorerId = gi < scorerIDs.count ? scorerIDs[gi] : 0
                let nonScorer = group.filter { $0.id != scorerId }
                return (0..<3).map { i in i < nonScorer.count ? nonScorer[i].id : nil }
            }
        }
        .alert("Remove Group?", isPresented: $showRemoveGroupConfirm) {
            Button("Remove", role: .destructive) {
                if let idx = removeGroupIndex {
                    removeGroup(at: idx)
                    removeGroupIndex = nil
                }
            }
            Button("Cancel", role: .cancel) { removeGroupIndex = nil }
        } message: {
            Text("This group has an invited scorer who will be removed.")
        }
    }

    // MARK: - Validation

    private var firstGroupMissingScorer: Int? {
        for gi in groups.indices {
            let slot = gi < scorerSlots.count ? scorerSlots[gi] : ScorerSlot()
            if slot.state == .empty { return gi + 1 }
        }
        return nil
    }

    private var firstPlayerMissingIndex: String? {
        for gi in groups.indices {
            let slots = gi < slotAssignments.count ? slotAssignments[gi] : []
            for si in 0..<3 {
                let key = "\(gi)-\(si)"
                // Only check unassigned slots (no player ID)
                guard si >= slots.count || slots[si] == nil else { continue }
                let name = emptySlotNames[key]?.trimmingCharacters(in: .whitespaces) ?? ""
                guard !name.isEmpty else { continue }
                let hc = emptySlotHCs[key]?.trimmingCharacters(in: .whitespaces) ?? ""
                if hc.isEmpty { return name }
            }
        }
        return nil
    }

    private var canSave: Bool { firstGroupMissingScorer == nil && firstPlayerMissingIndex == nil }

    private var saveHint: String? {
        if let group = firstGroupMissingScorer { return "Assign a scorer for Group \(group)" }
        if let name = firstPlayerMissingIndex { return "Missing index for \(name)" }
        return nil
    }

    // MARK: - Group Card

    private func groupCard(groupIndex: Int, players: [Player]) -> some View {
        let slots = groupIndex < slotAssignments.count ? slotAssignments[groupIndex] : [nil, nil, nil]

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("GROUP \(groupIndex + 1)")
                    .font(.carry.captionSemibold)
                    .foregroundColor(Color.textDisabled)
                Spacer()
                if groupIndex > 0 {
                    Button {
                        let slot = groupIndex < scorerSlots.count ? scorerSlots[groupIndex] : ScorerSlot()
                        if slot.state != .empty && slot.profileId != nil {
                            removeGroupIndex = groupIndex
                            showRemoveGroupConfirm = true
                        } else {
                            removeGroup(at: groupIndex)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text("—").font(.system(size: 13, weight: .bold))
                            Text("REMOVE").font(.carry.captionSemibold)
                        }
                        .foregroundColor(Color.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 4)
            .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 20) {
                // Score Keeper
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Score Keeper")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                        Spacer()
                        if groupIndex != 0 {
                            Text("*Carry app required")
                                .font(.carry.caption)
                                .foregroundColor(Color.textDisabled)
                        }
                    }

                    if groupIndex < scorerSlots.count {
                        let scorerColors = ["#4CAF50", "#2196F3", "#FF9800", "#E91E63", "#9C27B0", "#00BCD4", "#FF5722", "#607D8B"]
                        ScorerAssignmentView(
                            scorer: scorerSlotBinding(groupIndex: groupIndex),
                            excludeProfileIds: excludedScorerIds(exceptGroup: groupIndex),
                            groupLabel: "Group \(groupIndex + 1)",
                            defaultColor: scorerColors[(groupIndex * 4) % scorerColors.count],
                            readOnly: groupIndex == 0
                        )
                    }
                }

                // Players
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Group \(groupIndex + 1)")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                        Spacer()
                        Text("Index")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                            .padding(.trailing, 4)
                    }

                    VStack(spacing: 20) {
                        // Fixed 3 slots per group — positions never shift
                        ForEach(0..<3, id: \.self) { slotIndex in
                            if let playerId = slots[slotIndex],
                               let player = players.first(where: { $0.id == playerId }) {
                                playerRow(player: player, groupIndex: groupIndex, slotIndex: slotIndex)
                            } else {
                                emptyPlayerSlot(groupIndex: groupIndex, slotIndex: slotIndex)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.borderLight, lineWidth: 1)
            )
        }
        .padding(.bottom, 4)
    }

    // MARK: - Player Rows

    private func playerRow(player: Player, groupIndex: Int, slotIndex: Int) -> some View {
        let isCarryUser = player.profileId != nil && !player.isPendingInvite && !player.isGuest

        // For quick games, non-scorer Carry members show green avatar (not orange).
        // Only the scorer's pending state matters — guest slot players are treated as confirmed.
        let displayPlayer: Player = {
            if isQuickGame && isCarryUser && player.isPendingAccept {
                var p = player
                p.isPendingAccept = false
                return p
            }
            return player
        }()

        return HStack(spacing: 10) {
            // Name field with avatar for Carry users
            HStack(spacing: 8) {
                if isCarryUser {
                    PlayerAvatar(player: displayPlayer, size: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.name)
                            .font(.carry.bodySemibold)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)
                        let subtitle = [player.homeClub, player.handicap != 0 ? formatHandicap(player.handicap) : nil]
                            .compactMap { $0 }.joined(separator: " · ")
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.carry.caption)
                                .foregroundColor(Color(hexString: "#BFC0C2"))
                        }
                    }

                    Spacer()

                    Button {
                        clearPlayer(groupIndex: groupIndex, slotIndex: slotIndex)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color.textDisabled)
                    }
                    .buttonStyle(.plain)
                } else if player.isPendingInvite {
                    // SMS-invited player
                    PlayerAvatar(player: player, size: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.name)
                            .font(.carry.bodySemibold)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)
                        if let phone = player.phoneNumber {
                            Text(ScorerAssignmentView.formatPhone(phone))
                                .font(.carry.caption)
                                .foregroundColor(Color(hexString: "#BFC0C2"))
                        }
                    }

                    Spacer()

                    Button {
                        clearPlayer(groupIndex: groupIndex, slotIndex: slotIndex)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color.textDisabled)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Guest name text field (editable)
                    TextField("Enter name", text: guestNameBinding(player: player, groupIndex: groupIndex))
                        .font(.carry.bodyLG)
                        .foregroundColor(Color.textPrimary)

                    Spacer()

                    Button {
                        clearPlayer(groupIndex: groupIndex, slotIndex: slotIndex)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color.textDisabled)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.borderLight, lineWidth: 1)
            )

            hcButton(value: player.handicap, disabled: isCarryUser || player.isPendingInvite) {
                guard let idx = groups[groupIndex].firstIndex(where: { $0.id == player.id }) else { return }
                hcPickerValue = player.handicap
                hcPickerIsPlus = player.handicap < 0
                hcPickerCommit = { newVal, _ in
                    groups[groupIndex][idx].handicap = newVal
                }
                showHCPicker = true
            }
        }
    }

    private func emptyPlayerSlot(groupIndex: Int, slotIndex: Int) -> some View {
        let key = "\(groupIndex)-\(slotIndex)"
        let isActiveSearch = activePlayerSearchSlot?.group == groupIndex && activePlayerSearchSlot?.slot == slotIndex
        let showResults = isActiveSearch && !playerSearchResults.isEmpty
        let showInviteOption = isActiveSearch && (emptySlotNames[key] ?? "").trimmingCharacters(in: .whitespaces).count >= 2 && !showResults

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                CarryTextField(
                    "Enter name",
                    text: emptyNameSearchBinding(groupIndex: groupIndex, slotIndex: slotIndex),
                    onFocusChange: { isFocused in
                        if isFocused {
                            focusedEmptySlot = (group: groupIndex, slot: slotIndex)
                        } else if focusedEmptySlot?.group == groupIndex && focusedEmptySlot?.slot == slotIndex {
                            // Delay clearing so tap on search result registers first
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                if focusedEmptySlot?.group == groupIndex && focusedEmptySlot?.slot == slotIndex {
                                    focusedEmptySlot = nil
                                    playerSearchResults = []
                                    activePlayerSearchSlot = nil
                                }
                            }
                        }
                    }
                )

                hcButton(value: {
                    let str = emptySlotHCs[key] ?? ""
                    if str.hasPrefix("+") { return -(Double(String(str.dropFirst())) ?? 0) }
                    return Double(str) ?? 0
                }(), disabled: false, isPlaceholder: (emptySlotHCs[key] ?? "").isEmpty) {
                    let str = emptySlotHCs[key] ?? ""
                    let val: Double = str.hasPrefix("+") ? -(Double(String(str.dropFirst())) ?? 0) : Double(str) ?? 0
                    hcPickerValue = val
                    hcPickerIsPlus = val < 0
                    hcPickerCommit = { newVal, isPlus in
                        if isPlus && newVal < 0 {
                            emptySlotHCs[key] = "+\(String(format: "%.1f", abs(newVal)))"
                        } else {
                            emptySlotHCs[key] = String(format: "%.1f", newVal)
                        }
                    }
                    showHCPicker = true
                }
            }

            // Typeahead search results
            if showResults {
                playerTypeaheadOverlay(groupIndex: groupIndex, slotIndex: slotIndex)
            }

            // SMS invite option
            if showInviteOption {
                smsInviteRow(groupIndex: groupIndex, slotIndex: slotIndex)
            }
        }
        .zIndex(showResults || showInviteOption ? 10 : 0)
    }

    // MARK: - Search Typeahead

    @ViewBuilder
    private func playerTypeaheadOverlay(groupIndex: Int, slotIndex: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(playerSearchResults.prefix(3)) { profile in
                Button {
                    selectPlayerFromSearch(profile: profile, groupIndex: groupIndex, slotIndex: slotIndex)
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

                if profile.id != playerSearchResults.prefix(3).last?.id {
                    Divider().padding(.leading, 48)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderLight, lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.top, 4)
    }

    // MARK: - SMS Invite

    @ViewBuilder
    private func smsInviteRow(groupIndex: Int, slotIndex: Int) -> some View {
        let key = "\(groupIndex)-\(slotIndex)"
        let name = emptySlotNames[key] ?? ""

        VStack(alignment: .leading, spacing: 12) {
            Text("Send Invite to \"\(name)\"")
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
                    .onChange(of: phoneText) { _, newValue in
                        let digits = newValue.filter { $0.isNumber }
                        if digits.count > 10 {
                            phoneText = String(digits.prefix(10))
                        }
                    }
                    .onAppear {
                        phoneName = name
                        phoneText = ""
                    }

                let digits = phoneText.filter { $0.isNumber }
                Button {
                    sendSlotInvite(groupIndex: groupIndex, slotIndex: slotIndex)
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
        .padding(.top, 4)
    }

    private func hcButton(value: Double, disabled: Bool, isPlaceholder: Bool = false, onTap: @escaping () -> Void) -> some View {
        Button {
            guard !disabled else { return }
            onTap()
        } label: {
            Text(isPlaceholder ? "HC" : formatHandicap(value))
                .font(.carry.bodyLG)
                .foregroundColor(isPlaceholder ? Color.textDisabled : Color.textPrimary)
                .frame(width: 56, height: 50)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Bindings

    private func guestNameBinding(player: Player, groupIndex: Int) -> Binding<String> {
        Binding(
            get: { player.name },
            set: { newValue in
                guard let idx = groups[groupIndex].firstIndex(where: { $0.id == player.id }) else { return }
                groups[groupIndex][idx].name = newValue
            }
        )
    }

    private func emptyNameBinding(groupIndex: Int, slotIndex: Int) -> Binding<String> {
        let key = "\(groupIndex)-\(slotIndex)"
        return Binding(
            get: { emptySlotNames[key] ?? "" },
            set: { emptySlotNames[key] = $0 }
        )
    }

    /// Like emptyNameBinding but also triggers player search on every keystroke.
    private func emptyNameSearchBinding(groupIndex: Int, slotIndex: Int) -> Binding<String> {
        let key = "\(groupIndex)-\(slotIndex)"
        return Binding(
            get: { emptySlotNames[key] ?? "" },
            set: { newValue in
                emptySlotNames[key] = newValue
                debouncePlayerSearch(query: newValue, groupIndex: groupIndex, slotIndex: slotIndex)
            }
        )
    }

    private func emptyHCBinding(groupIndex: Int, slotIndex: Int) -> Binding<String> {
        let key = "\(groupIndex)-\(slotIndex)"
        return Binding(
            get: { emptySlotHCs[key] ?? "" },
            set: { newValue in
                let filtered = filterHandicapInput(newValue)
                if filtered != newValue {
                    emptySlotHCs[key] = newValue
                    DispatchQueue.main.async { emptySlotHCs[key] = filtered }
                } else {
                    emptySlotHCs[key] = filtered
                }
            }
        )
    }

    private func scorerSlotBinding(groupIndex: Int) -> Binding<ScorerSlot> {
        Binding(
            get: {
                guard groupIndex < scorerSlots.count else { return ScorerSlot() }
                return scorerSlots[groupIndex]
            },
            set: { newValue in
                guard groupIndex < scorerSlots.count else { return }
                let oldValue = scorerSlots[groupIndex]
                scorerSlots[groupIndex] = newValue

                if let profileId = newValue.profileId, oldValue.profileId != profileId {
                    var player = newValue.asPlayer
                    // Carry user picked from search — mark as pending until
                    // they accept. Exception: if the selected player is the
                    // current user (creator reassigning themselves), skip
                    // the pending-accept — they're the one doing the action.
                    player.isPendingAccept = (player.id != currentUserId)

                    // Move semantics: if the selected player is already in
                    // another group (either as a player or that group's
                    // scorer), remove them from there before placing them
                    // as this group's scorer. Prevents a player ending up
                    // in two groups at once — which is what would otherwise
                    // happen when the creator searches themselves back in.
                    for gi in 0..<groups.count where gi != groupIndex {
                        if let prevIdx = groups[gi].firstIndex(where: { $0.id == player.id }) {
                            groups[gi].remove(at: prevIdx)
                            if gi < scorerIDs.count && scorerIDs[gi] == player.id {
                                // Clear the now-empty scorer slot — the
                                // missing-scorer banner will surface on
                                // that group until a new scorer is added.
                                scorerIDs[gi] = 0
                            }
                            // Clear them from that group's UI slot assignments
                            // too so the non-scorer slot list renders correctly.
                            if gi < slotAssignments.count {
                                for slotIdx in slotAssignments[gi].indices
                                where slotAssignments[gi][slotIdx] == player.id {
                                    slotAssignments[gi][slotIdx] = nil
                                }
                            }
                        }
                    }

                    // Within-group promotion: if the selected player is a
                    // Carry member currently occupying a NON-scorer slot of
                    // THIS group, clear that slot. Without this, they'd
                    // appear twice — once as the scorer at the top, once
                    // as a player in the list below. Guests can't reach
                    // this branch (profileId is nil in search results).
                    if groupIndex < slotAssignments.count {
                        for slotIdx in slotAssignments[groupIndex].indices
                        where slotAssignments[groupIndex][slotIdx] == player.id {
                            slotAssignments[groupIndex][slotIdx] = nil
                        }
                    }

                    if let existingIdx = groups[groupIndex].firstIndex(where: { $0.id == player.id }) {
                        // Already in this group — just update pending status
                        groups[groupIndex][existingIdx].isPendingAccept = player.isPendingAccept
                    } else {
                        groups[groupIndex].append(player)
                    }
                    scorerIDs[groupIndex] = player.id
                } else if newValue.isPendingInvite && !oldValue.isPendingInvite {
                    let player = newValue.asPlayer
                    groups[groupIndex].append(player)
                    scorerIDs[groupIndex] = player.id
                } else if newValue.state == .empty && oldValue.state != .empty {
                    // Scorer cleared — never auto-assign (especially not a
                    // guest). Leave 0 so the creator explicitly picks one.
                    scorerIDs[groupIndex] = 0
                }
            }
        )
    }

    private func excludedScorerIds(exceptGroup: Int) -> Set<UUID> {
        var ids = Set<UUID>()
        for (gi, slot) in scorerSlots.enumerated() {
            if gi == exceptGroup { continue }
            if let pid = slot.profileId { ids.insert(pid) }
        }
        // The creator/current user is intentionally NOT excluded — they may
        // want to search themselves back in as a scorer after moving to
        // another group. The scorer binding setter below handles the
        // "move from previous slot" case so we don't end up with the same
        // person placed in two groups.
        return ids
    }

    // MARK: - Player Search

    private func debouncePlayerSearch(query: String, groupIndex: Int, slotIndex: Int) {
        playerSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            playerSearchResults = []
            activePlayerSearchSlot = nil
            return
        }
        activePlayerSearchSlot = (group: groupIndex, slot: slotIndex)
        playerSearchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do {
                let results = try await PlayerSearchService.shared.searchPlayers(query: trimmed)
                // Filter out players already in any group + all scorers + creator
                var usedIds = Set<UUID>()
                for group in groups {
                    for player in group {
                        if let pid = player.profileId { usedIds.insert(pid) }
                    }
                }
                for slot in scorerSlots {
                    if let pid = slot.profileId { usedIds.insert(pid) }
                }
                if let creatorProfileId = allMembers.first(where: { $0.id == currentUserId })?.profileId {
                    usedIds.insert(creatorProfileId)
                }
                let filtered = results.filter { !usedIds.contains($0.id) }
                await MainActor.run {
                    playerSearchResults = filtered
                    if filtered.isEmpty {
                        // Keep activePlayerSearchSlot so SMS invite shows
                    }
                }
            } catch {
                await MainActor.run {
                    playerSearchResults = []
                }
            }
        }
    }

    private func selectPlayerFromSearch(profile: ProfileDTO, groupIndex: Int, slotIndex: Int) {
        // Create player from profile — for quick games, don't mark as pending (green avatar)
        let player = Player(
            id: Player.stableId(from: profile.id),
            name: "\(profile.firstName) \(profile.lastName)".trimmingCharacters(in: .whitespaces),
            initials: String(profile.firstName.prefix(1) + profile.lastName.prefix(1)).uppercased(),
            color: profile.color,
            handicap: profile.handicap,
            avatar: "",
            group: groupIndex + 1,
            ghinNumber: nil,
            venmoUsername: nil,
            avatarUrl: profile.avatarUrl,
            isPendingAccept: isQuickGame ? false : true,
            profileId: profile.id,
            homeClub: profile.homeClub
        )

        // Add to groups array
        groups[groupIndex].append(player)

        // Assign to fixed slot position
        if groupIndex < slotAssignments.count {
            slotAssignments[groupIndex][slotIndex] = player.id
        }

        // Clear search state
        let key = "\(groupIndex)-\(slotIndex)"
        emptySlotNames[key] = nil
        emptySlotHCs[key] = nil
        playerSearchResults = []
        activePlayerSearchSlot = nil
        focusedEmptySlot = nil
    }

    private func sendSlotInvite(groupIndex: Int, slotIndex: Int) {
        let digits = phoneText.filter { $0.isNumber }
        guard digits.count >= 10 else { return }

        let key = "\(groupIndex)-\(slotIndex)"
        let name = (emptySlotNames[key] ?? "").trimmingCharacters(in: .whitespaces)
        let displayName = name.isEmpty ? ScorerAssignmentView.formatPhone(digits) : name
        let guestColors = ["#E67E22", "#9B59B6", "#1ABC9C", "#C0392B", "#2980B9", "#27AE60"]
        let colorIdx = (nextGuestID - 100) % guestColors.count

        let player = Player(
            id: nextGuestID,
            name: displayName,
            initials: String(displayName.prefix(2)).uppercased(),
            color: guestColors[colorIdx],
            handicap: 0,
            avatar: "",
            group: groupIndex + 1,
            ghinNumber: nil,
            venmoUsername: nil,
            phoneNumber: digits,
            isPendingInvite: true,
            profileId: nil
        )
        nextGuestID += 1

        // Add to groups array
        groups[groupIndex].append(player)

        // Assign to fixed slot position
        if groupIndex < slotAssignments.count {
            slotAssignments[groupIndex][slotIndex] = player.id
        }

        // Open native SMS
        let body = "Score our skins game on Carry! Download: https://carryapp.site"
        let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "sms:\(digits)&body=\(encoded)") {
            UIApplication.shared.open(url)
        }

        // Clear search + invite state
        emptySlotNames[key] = nil
        emptySlotHCs[key] = nil
        playerSearchResults = []
        activePlayerSearchSlot = nil
        phoneText = ""
        phoneName = ""
        focusedEmptySlot = nil
    }

    // MARK: - Actions

    private func clearPlayer(groupIndex: Int, slotIndex: Int) {
        // Find the player ID assigned to this slot
        guard groupIndex < slotAssignments.count,
              slotIndex < slotAssignments[groupIndex].count,
              let playerId = slotAssignments[groupIndex][slotIndex] else { return }

        // Clear the slot assignment (position preserved — no shifting)
        slotAssignments[groupIndex][slotIndex] = nil

        // Remove from groups array
        if let idx = groups[groupIndex].firstIndex(where: { $0.id == playerId }) {
            groups[groupIndex].remove(at: idx)
        }

        // Clear any stale empty slot data for this position
        let key = "\(groupIndex)-\(slotIndex)"
        emptySlotNames[key] = nil
        emptySlotHCs[key] = nil
    }

    private func removeGroup(at index: Int) {
        guard groups.count > 1, index < groups.count else { return }
        let removedPlayers = groups[index]
        withAnimation(.easeOut(duration: 0.2)) {
            groups.remove(at: index)
            if index < scorerIDs.count { scorerIDs.remove(at: index) }
            if index < teeTimes.count { teeTimes.remove(at: index) }
            if index < startingSides.count { startingSides.remove(at: index) }
            if index < selectedTees.count { selectedTees.remove(at: index) }
            if index < scorerSlots.count { scorerSlots.remove(at: index) }
            if index < slotAssignments.count { slotAssignments.remove(at: index) }

            // Clean up emptySlotNames/HCs for removed group and re-key remaining
            var newNames: [String: String] = [:]
            var newHCs: [String: String] = [:]
            for gi in groups.indices {
                for si in 0..<3 {
                    let oldGi = gi >= index ? gi + 1 : gi
                    let oldKey = "\(oldGi)-\(si)"
                    let newKey = "\(gi)-\(si)"
                    if let name = emptySlotNames[oldKey] { newNames[newKey] = name }
                    if let hc = emptySlotHCs[oldKey] { newHCs[newKey] = hc }
                }
            }
            emptySlotNames = newNames
            emptySlotHCs = newHCs

            for player in removedPlayers {
                if let minIdx = groups.indices.min(by: { groups[$0].count < groups[$1].count }),
                   groups[minIdx].count < maxGroupSize {
                    groups[minIdx].append(player)
                    // Find first empty slot in target group
                    if minIdx < slotAssignments.count {
                        let scorerId = minIdx < scorerIDs.count ? scorerIDs[minIdx] : 0
                        if player.id != scorerId {
                            if let emptySlot = slotAssignments[minIdx].firstIndex(where: { $0 == nil }) {
                                slotAssignments[minIdx][emptySlot] = player.id
                            }
                        }
                    }
                }
            }
            syncTeeTimes()
            syncScorerIDs()
        }
    }

    private func syncTeeTimes() {
        while teeTimes.count < groups.count { teeTimes.append(nil) }
        while teeTimes.count > groups.count { teeTimes.removeLast() }
    }

    private func syncScorerIDs() {
        while scorerIDs.count < groups.count {
            // Never auto-assign a guest or phone invite — they can't score.
            // If no valid Carry user exists yet, leave 0 so the missing-scorer
            // banner prompts the creator to pick someone.
            let firstConfirmed = groups[scorerIDs.count].first(where: {
                !$0.isGuest && !$0.isPendingInvite && !$0.isPendingAccept && $0.profileId != nil
            })
            scorerIDs.append(firstConfirmed?.id ?? 0)
        }
        while scorerIDs.count > groups.count { scorerIDs.removeLast() }
    }

    // MARK: - Save

    private func saveAndDismiss() async {
        // Step 0: Build clean groups from slotAssignments FIRST.
        // This is the single source of truth — all server operations use this.
        let guestColors = ["#E67E22", "#9B59B6", "#1ABC9C", "#C0392B", "#2980B9", "#27AE60"]
        let guestAvatars = ["👤", "🎩", "🧢", "🕶️", "⛳", "🏌️"]

        // Create guest profiles for filled empty slots (need UUIDs before building clean groups)
        var newGuests: [(name: String, hc: Double, groupIndex: Int, slotIndex: Int)] = []
        for gi in groups.indices {
            let slots = gi < slotAssignments.count ? slotAssignments[gi] : []
            for si in 0..<3 {
                guard si >= slots.count || slots[si] == nil else { continue }
                let key = "\(gi)-\(si)"
                let name = emptySlotNames[key]?.trimmingCharacters(in: .whitespaces) ?? ""
                let hcStr = emptySlotHCs[key] ?? ""
                guard !name.isEmpty else { continue }
                let hc = hcStr.hasPrefix("+")
                    ? -(Double(String(hcStr.dropFirst())) ?? 0.0)
                    : Double(hcStr) ?? 0.0
                newGuests.append((name: name, hc: hc, groupIndex: gi, slotIndex: si))
            }
        }

        guard let groupId = supabaseGroupId else {
            // No server — just add guests locally and return clean result
            for guest in newGuests {
                let colorIdx = (nextGuestID - 100) % guestColors.count
                let player = Player(
                    id: nextGuestID,
                    name: guest.name,
                    initials: String(guest.name.prefix(2)).uppercased(),
                    color: guestColors[colorIdx],
                    handicap: guest.hc,
                    avatar: guestAvatars[(nextGuestID - 100) % guestAvatars.count],
                    group: guest.groupIndex + 1,
                    ghinNumber: nil, venmoUsername: nil,
                    isGuest: true
                )
                groups[guest.groupIndex].append(player)
                slotAssignments[guest.groupIndex][guest.slotIndex] = player.id
                nextGuestID += 1
            }
            onSave(buildResult())
            ToastManager.shared.success("Groups updated")
            return
        }

        // 1. Create guest profiles on server
        if !newGuests.isEmpty {
            do {
                let userId = try await SupabaseManager.shared.client.auth.session.user.id
                let guestService = GuestProfileService()
                let names = newGuests.map(\.name)
                let initials = newGuests.map { String($0.name.prefix(2)).uppercased() }
                let handicaps = newGuests.map(\.hc)
                let colors = newGuests.map { _ in guestColors[Int.random(in: 0..<guestColors.count)] }

                let uuids = try await guestService.createGuestProfiles(
                    names: names, initials: initials,
                    handicaps: handicaps, colors: colors,
                    creatorId: userId
                )
                guard uuids.count == newGuests.count else {
                    ToastManager.shared.error("Failed to create guest profiles")
                    return
                }

                await MainActor.run {
                    for (i, guestInfo) in newGuests.enumerated() {
                        let uuid = uuids[i]
                        let colorIdx = (nextGuestID - 100) % guestColors.count
                        let avatarIdx = (nextGuestID - 100) % guestAvatars.count
                        let player = Player(
                            id: Player.stableId(from: uuid),
                            name: guestInfo.name,
                            initials: String(guestInfo.name.prefix(2)).uppercased(),
                            color: guestColors[colorIdx],
                            handicap: guestInfo.hc,
                            avatar: guestAvatars[avatarIdx],
                            group: guestInfo.groupIndex + 1,
                            ghinNumber: nil, venmoUsername: nil,
                            avatarImageName: nil, avatarUrl: nil,
                            isGuest: true, profileId: uuid
                        )
                        groups[guestInfo.groupIndex].append(player)
                        // Track in slotAssignments so buildResult() includes them
                        if guestInfo.groupIndex < slotAssignments.count {
                            slotAssignments[guestInfo.groupIndex][guestInfo.slotIndex] = player.id
                        }
                        allMembers.append(player)
                        selectedIDs.insert(player.id)
                        nextGuestID += 1
                    }
                }

                let memberInserts = newGuests.enumerated().map { (i, guestInfo) in
                    GroupMemberInsert(
                        groupId: groupId, playerId: uuids[i],
                        role: "member", status: "active",
                        groupNum: guestInfo.groupIndex + 1
                    )
                }
                try await SupabaseManager.shared.client
                    .from("group_members")
                    .insert(memberInserts)
                    .execute()
            } catch {
                #if DEBUG
                print("[PlayerGroupsSheet] Failed to create guests: \(error)")
                #endif
                await MainActor.run { ToastManager.shared.error("Failed to add players") }
                return
            }
        }

        // 2. Build the clean groups (scorer + slotAssignment players only)
        let cleanResult = await MainActor.run { buildResult() }
        let cleanProfileIds: Set<UUID> = Set(cleanResult.groups.flatMap { $0 }.compactMap(\.profileId))

        // 3. Sync group_members to match clean groups:
        //    - Activate/insert members IN clean groups
        //    - Remove members NOT in clean groups
        do {
            let existingMembers: [GroupMemberDTO] = (try? await SupabaseManager.shared.client
                .from("group_members")
                .select()
                .eq("group_id", value: groupId.uuidString)
                .execute()
                .value) ?? []

            let activeOrInvitedIds = Set(existingMembers
                .filter { $0.status == "active" || $0.status == "invited" }
                .map(\.playerId))

            // 3a. Ensure every player in clean groups has an active row
            for (gi, group) in cleanResult.groups.enumerated() {
                for player in group where !player.isGuest {
                    guard let profileId = player.profileId else { continue }
                    if !activeOrInvitedIds.contains(profileId) {
                        let hasExistingRow = existingMembers.contains(where: { $0.playerId == profileId })
                        if hasExistingRow {
                            let updates: [String: String] = ["status": "active"]
                            _ = try? await SupabaseManager.shared.client
                                .from("group_members")
                                .update(updates)
                                .eq("group_id", value: groupId.uuidString)
                                .eq("player_id", value: profileId.uuidString)
                                .execute()
                        } else {
                            // New Carry user added by the creator — must accept
                            // via their home screen. Inserting as "invited" (not
                            // "active") ensures they show as pending until they
                            // tap Accept, matching the rest of the invite flow.
                            let insert = GroupMemberInsert(
                                groupId: groupId,
                                playerId: profileId,
                                role: "member",
                                status: "invited",
                                groupNum: gi + 1
                            )
                            _ = try? await SupabaseManager.shared.client
                                .from("group_members")
                                .insert(insert)
                                .execute()
                        }
                    }
                }
            }

            // 3b. Remove members NOT in clean groups (mark as "removed")
            for member in existingMembers where member.status == "active" || member.status == "invited" {
                if !cleanProfileIds.contains(member.playerId) {
                    let updates: [String: String] = ["status": "removed"]
                    _ = try? await SupabaseManager.shared.client
                        .from("group_members")
                        .update(updates)
                        .eq("group_id", value: groupId.uuidString)
                        .eq("player_id", value: member.playerId.uuidString)
                        .execute()
                }
            }
        }

        // 4. Persist group_num assignments + scorer IDs using clean groups
        do {
            var assignments: [(playerId: UUID, groupNum: Int)] = []
            for (gi, group) in cleanResult.groups.enumerated() {
                for player in group {
                    if let profileId = player.profileId {
                        assignments.append((playerId: profileId, groupNum: gi + 1))
                    }
                }
            }
            if !assignments.isEmpty {
                try await GroupService().saveGroupNums(groupId: groupId, assignments: assignments)
                // Mirror group_num into round_players for any active/concluded
                // round so scorecards mid-flight pick up the rearrangement.
                try? await RoundService().syncRoundPlayersGroupNums(
                    groupId: groupId,
                    assignments: assignments
                )
            }
            try await GroupService().updateGroup(
                groupId: groupId,
                update: SkinsGroupUpdate(scorerIds: scorerIDs)
            )
        } catch {
            #if DEBUG
            print("[PlayerGroupsSheet] Failed to persist: \(error)")
            #endif
        }

        // 5. Return clean result to parent
        await MainActor.run {
            onSave(cleanResult)
            ToastManager.shared.success("Groups updated")
        }
    }

    private func buildResult() -> PlayerGroupsResult {
        // Reconstruct clean groups from slotAssignments + scorer.
        // This prevents any untracked players in the raw groups array
        // from leaking through and creating duplicates.
        var cleanGroups: [[Player]] = []
        for gi in groups.indices {
            var groupPlayers: [Player] = []

            // 1. Add scorer
            let scorerId = gi < scorerIDs.count ? scorerIDs[gi] : 0
            if let scorer = groups[gi].first(where: { $0.id == scorerId }) {
                groupPlayers.append(scorer)
            }

            // 2. Add players from slot assignments (preserves slot order)
            let slots = gi < slotAssignments.count ? slotAssignments[gi] : []
            for si in 0..<slots.count {
                guard let playerId = slots[si],
                      let player = groups[gi].first(where: { $0.id == playerId }) else { continue }
                // Don't double-add if scorer happens to be in a slot
                if player.id == scorerId { continue }
                groupPlayers.append(player)
            }

            cleanGroups.append(groupPlayers)
        }

        return PlayerGroupsResult(
            groups: cleanGroups,
            scorerIDs: scorerIDs,
            teeTimes: teeTimes,
            startingSides: startingSides,
            selectedTees: selectedTees,
            allMembers: allMembers,
            selectedIDs: selectedIDs,
            nextGuestID: nextGuestID
        )
    }
}
