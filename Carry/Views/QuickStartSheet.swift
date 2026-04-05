import SwiftUI

// MARK: - PlayerSlot

private struct PlayerSlot: Identifiable {
    let id = UUID()
    var name: String = ""
    var handicap: String = ""
    var existingProfileId: UUID? = nil
    var color: String = "#999999"
    var isPendingInvite: Bool = false
    var phoneNumber: String? = nil

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var isEmpty: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }
}

// MARK: - Color Palette

private let slotColors = [
    "#4CAF50", "#2196F3", "#FF9800", "#E91E63",
    "#9C27B0", "#00BCD4", "#FF5722", "#607D8B",
    "#8BC34A", "#3F51B5", "#FFC107", "#F44336",
    "#673AB7", "#009688", "#795548", "#CDDC39"
]

// MARK: - QuickGameSheet

struct QuickGameSheet: View {
    let currentUser: Player
    let recentQuickGames: [SavedGroup]
    let onCreate: (SavedGroup) -> Void

    @State private var selectedRecentGameId: UUID? = nil
    @State private var selectedCourse: SelectedCourse?
    @State private var buyInAmount: Double = 0
    @State private var handicapPct: Double = 1.0
    @State private var groupCount: Int = 1
    @State private var slots: [[PlayerSlot]] = []
    @State private var isCreating = false
    @State private var showCourseSheet = false
    @State private var showTeeTimePicker = false
    @State private var teeTimeDate: Date = {
        // Default to next half-hour from now
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let minute = comps.minute ?? 0
        if minute < 30 {
            comps.minute = 30
        } else {
            comps.minute = 0
            comps.hour = (comps.hour ?? 0) + 1
        }
        return cal.date(from: comps) ?? now
    }()
    @State private var hasTeeTime = false
    @State private var consecutiveInterval: Int = 10  // default 10 min between groups

    // Scorer search state
    @State private var scorerSearchText: String = ""
    @State private var scorerSearchResults: [ProfileDTO] = []
    @State private var scorerSearchGroupIndex: Int? = nil
    @State private var isScorerSearching = false
    @State private var scorerSearchTask: Task<Void, Never>?
    @State private var showInlinePhoneEntry = false
    @State private var inlinePhoneText = ""
    @State private var inlinePhoneName = ""

    // Player name typeahead state
    @State private var playerSearchResults: [ProfileDTO] = []
    @State private var playerSearchTask: Task<Void, Never>?
    @State private var activePlayerSearchSlot: (group: Int, slot: Int)? = nil

    @FocusState private var focusedField: SlotField?

    @Environment(\.dismiss) private var dismiss

    private enum SlotField: Hashable {
        case name(group: Int, slot: Int)
        case handicap(group: Int, slot: Int)
        case scorerSearch(group: Int)
        case inlinePhone(group: Int)
    }

    // MARK: - Computed

    private var filledPlayerCount: Int {
        slots.prefix(groupCount).joined().filter { !$0.isEmpty }.count
    }

    private var isFormValid: Bool {
        guard selectedCourse != nil else { return false }
        guard groupCount >= 1 else { return false }
        guard filledPlayerCount >= 2 else { return false }
        // Every group with players must have a scorer (slot 0 with profileId)
        for g in 0..<groupCount {
            let hasPlayers = slots[g].contains { !$0.isEmpty }
            if hasPlayers && slots[g][0].existingProfileId == nil && !slots[g][0].isPendingInvite { return false }
        }
        // Every player with a name must have a handicap
        guard !hasPlayersWithoutHandicap else { return false }
        return true
    }

    private var hasPlayersWithoutHandicap: Bool {
        for g in 0..<groupCount {
            for slot in slots[g] where !slot.isEmpty {
                if slot.handicap.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            }
        }
        return false
    }

    // MARK: - Init

    init(currentUser: Player, recentQuickGames: [SavedGroup] = [], onCreate: @escaping (SavedGroup) -> Void) {
        self.currentUser = currentUser
        self.recentQuickGames = recentQuickGames
        self.onCreate = onCreate

        var initialSlots: [[PlayerSlot]] = []
        for groupIndex in 0..<4 {
            var group: [PlayerSlot] = []
            for slotIndex in 0..<4 {
                var slot = PlayerSlot()
                if groupIndex == 0 && slotIndex == 0 {
                    slot.name = currentUser.name
                    slot.handicap = String(format: "%.1f", currentUser.handicap)
                    slot.existingProfileId = currentUser.profileId
                    slot.color = currentUser.color
                } else {
                    slot.color = slotColors[(groupIndex * 4 + slotIndex) % slotColors.count]
                }
                group.append(slot)
            }
            initialSlots.append(group)
        }
        _slots = State(initialValue: initialSlots)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Sheet title
            Text("Quick Game")
                .font(.carry.sectionTitle)
                .foregroundColor(Color.pureBlack)
                .padding(.top, 40)
                .padding(.bottom, 24)

            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    recentSetupsSection
                    courseSection
                    teeTimeSection
                    buyInSection
                    handicapAllowanceSection
                    playerGroupsSection
                    continueButton
                }
                .padding(.bottom, 40)
            }
            .onTapGesture {
                focusedField = nil
                playerSearchResults = []
                activePlayerSearchSlot = nil
            }
            .onChange(of: focusedField) { _, newField in
                // Dismiss player typeahead when focus leaves the active name field
                if let active = activePlayerSearchSlot {
                    let stillOnNameField: Bool
                    if case .name(let g, let s) = newField, g == active.group, s == active.slot {
                        stillOnNameField = true
                    } else {
                        stillOnNameField = false
                    }
                    if !stillOnNameField {
                        playerSearchResults = []
                        activePlayerSearchSlot = nil
                    }
                }

                guard let field = newField else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    switch field {
                    case .name(let group, let slot), .handicap(let group, let slot):
                        scrollProxy.scrollTo("slot-\(group)-\(slot)", anchor: .center)
                    case .scorerSearch(let group), .inlinePhone(let group):
                        scrollProxy.scrollTo("slot-\(group)-0", anchor: .center)
                    }
                }
            }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .sheet(isPresented: $showCourseSheet) {
            CourseSelectionView { course in
                selectedCourse = course
                showCourseSheet = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTeeTimePicker) {
            teeTimePickerSheet
                .presentationDetents([.height(580)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Recent Setups

    @ViewBuilder
    private var recentSetupsSection: some View {
        let recents = recentQuickGames.prefix(3)
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent Setups")
                    .font(.carry.bodySMBold)
                    .foregroundColor(Color.textPrimary)
                    .padding(.leading, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(recents)) { game in
                            let isSelected = selectedRecentGameId == game.id
                            Button {
                                selectedRecentGameId = game.id
                                prefillFromRecentGame(game)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(game.lastCourse?.courseName ?? "Unknown")
                                        .font(.carry.bodySMSemibold)
                                        .foregroundColor(Color.textPrimary)
                                        .lineLimit(1)

                                    Text(game.name)
                                        .font(.carry.captionLG)
                                        .foregroundColor(Color.textTertiary)
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 10))
                                        Text("\(game.members.count)")
                                            .font(.carry.caption)
                                        if game.buyInPerPlayer > 0 {
                                            Text("·")
                                                .font(.carry.caption)
                                            Text("$\(Int(game.buyInPerPlayer))")
                                                .font(.carry.caption)
                                        }
                                    }
                                    .foregroundColor(Color.textDisabled)
                                }
                                .frame(width: 125)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(isSelected ? Color.textPrimary : Color.borderLight, lineWidth: isSelected ? 1.5 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private func prefillFromRecentGame(_ game: SavedGroup) {
        // Course
        selectedCourse = game.lastCourse

        // Buy-in & handicap
        buyInAmount = game.buyInPerPlayer
        handicapPct = game.handicapPercentage

        // Rebuild slots from game members
        // Sort each group so Carry users (scorers) come first in slot 0
        var newSlots: [[PlayerSlot]] = []
        let grouped = Dictionary(grouping: game.members, by: { $0.group })
        let maxGroup = grouped.keys.max() ?? 1

        for g in 0..<4 {
            var group: [PlayerSlot] = []
            let players = grouped[g + 1] ?? []

            // Sort: creator first (group 0), then Carry users (scorer), then guests
            let sorted: [Player]
            if g == 0 {
                // Group 1: creator always slot 0, then others
                let creator = players.filter { $0.profileId == currentUser.profileId }
                let rest = players.filter { $0.profileId != currentUser.profileId }
                sorted = creator + rest
            } else {
                // Other groups: Carry users (non-guest with profileId) first as scorer
                let carryUsers = players.filter { !$0.isGuest && $0.profileId != nil }
                let guests = players.filter { $0.isGuest || $0.profileId == nil }
                sorted = carryUsers + guests
            }

            for s in 0..<4 {
                var slot = PlayerSlot()
                let colorIdx = (g * 4 + s) % slotColors.count
                slot.color = slotColors[colorIdx]

                if s < sorted.count {
                    let player = sorted[s]
                    if g == 0 && s == 0 {
                        // Creator slot
                        slot.name = currentUser.name
                        slot.handicap = String(format: "%.1f", currentUser.handicap)
                        slot.existingProfileId = currentUser.profileId
                        slot.color = currentUser.color
                    } else if player.isGuest {
                        // Guest — fill name + HC but no profileId
                        slot.name = player.name
                        slot.handicap = String(format: "%.1f", player.handicap)
                    } else if let profileId = player.profileId {
                        // Carry user — fill everything (goes to slot 0 as scorer)
                        slot.name = player.name
                        slot.handicap = String(format: "%.1f", player.handicap)
                        slot.existingProfileId = profileId
                        slot.color = player.color
                    }
                }
                group.append(slot)
            }
            newSlots.append(group)
        }

        slots = newSlots
        groupCount = min(max(maxGroup, 1), 4)
    }

    // MARK: - Course Section

    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Course")
                .font(.carry.bodySMBold)
                .foregroundColor(Color.textPrimary)
                .padding(.leading, 4)

            Button {
                showCourseSheet = true
            } label: {
                if let course = selectedCourse {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.courseName)
                                .font(.carry.bodySemibold)
                                .foregroundColor(Color.textPrimary)
                            if let tee = course.teeBox {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hexString: tee.color))
                                        .frame(width: 8, height: 8)
                                    Text(tee.name)
                                        .font(.carry.caption)
                                        .foregroundColor(Color.textTertiary)
                                    Text("\u{00B7}")
                                        .foregroundColor(Color.textDisabled)
                                    Text(String(format: "%.1f / %d", tee.courseRating, tee.slopeRating))
                                        .font(.carry.caption)
                                        .foregroundColor(Color.textTertiary)
                                }
                            }
                        }
                        Spacer()
                        Text("Change")
                            .font(.carry.captionLG)
                            .foregroundColor(Color.textTertiary)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderLight, lineWidth: 1))
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "flag.fill")
                            .font(.carry.bodySM)
                            .foregroundColor(Color.textPrimary)
                        Text("Select a Course")
                            .font(.carry.bodyLG)
                            .foregroundColor(Color.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.carry.micro)
                            .foregroundColor(Color.textDisabled)
                    }
                    .frame(minHeight: 22)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderLight, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Tee Time Section

    private var teeTimeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tee Time")
                    .font(.carry.bodySMBold)
                    .foregroundColor(Color.textPrimary)
                    .padding(.leading, 4)
                Spacer()
                Text("*Tee times can be updated")
                    .font(.carry.caption)
                    .foregroundColor(Color.textDisabled)
            }

            Button {
                showTeeTimePicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.fill")
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textPrimary)
                    if hasTeeTime {
                        let formatter: DateFormatter = {
                            let f = DateFormatter()
                            f.dateFormat = "h:mm a"
                            return f
                        }()
                        Text(formatter.string(from: teeTimeDate))
                            .font(.carry.bodyLG)
                            .foregroundColor(Color.textPrimary)
                        if consecutiveInterval > 0 {
                            Text("\u{00B7} +\(consecutiveInterval) min between groups")
                                .font(.carry.caption)
                                .foregroundColor(Color.textTertiary)
                        }
                    } else {
                        Text("Add Tee Time")
                            .font(.carry.bodyLG)
                            .foregroundColor(Color.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.carry.micro)
                        .foregroundColor(Color.textDisabled)
                }
                .frame(minHeight: 22)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderLight, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Tee Time Picker Sheet (matches GroupManagerView pattern)

    @State private var initialTeeTimeDate = Date()
    @State private var initialConsecutiveInterval: Int = 0

    private var teeTimeHasChanged: Bool {
        teeTimeDate != initialTeeTimeDate || consecutiveInterval != initialConsecutiveInterval
    }

    private var teeTimePickerSheet: some View {
        VStack(spacing: 0) {
            Text("Set Tee Time")
                .font(.carry.labelBold)
                .foregroundColor(Color.textPrimary)
                .padding(.top, 24)
                .padding(.bottom, 44)

            DatePicker(
                "",
                selection: $teeTimeDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 160)
            .clipped()
            .padding(.horizontal, 40)

            Text("Consecutive Tee Times")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color.textPrimary)
                .padding(.top, 44)
                .padding(.bottom, 16)

            HStack(spacing: 10) {
                ForEach([0, 8, 10, 12], id: \.self) { minutes in
                    Button {
                        consecutiveInterval = minutes
                    } label: {
                        Text(minutes == 0 ? "Off" : "+\(minutes) min")
                            .font(.carry.bodySMSemibold)
                            .foregroundColor(consecutiveInterval == minutes ? .white : Color.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(consecutiveInterval == minutes ? Color.textPrimary : Color.bgPrimary)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                hasTeeTime = true
                showTeeTimePicker = false
            } label: {
                Text("Set Tee Time")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 19)
                            .fill(Color.textPrimary)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.top, 80)
            .padding(.bottom, 24)
        }
        .onAppear {
            initialTeeTimeDate = teeTimeDate
            initialConsecutiveInterval = consecutiveInterval
        }
    }

    // MARK: - Buy-In Section

    private var buyInSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Buy-In per Player")
                .font(.carry.bodySMBold)
                .foregroundColor(Color.textPrimary)
                .padding(.leading, 4)

            VStack(spacing: 8) {
                HStack {
                    Text("$\(Int(buyInAmount))")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color.textPrimary)
                        .monospacedDigit()
                    Spacer()
                    if buyInAmount > 0, filledPlayerCount >= 2 {
                        Text("Pot: $\(Int(buyInAmount) * filledPlayerCount)")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.goldAccent)
                    }
                }

                Slider(value: $buyInAmount, in: 0...1000, step: 5)
                    .tint(Color.goldAccent)

                HStack {
                    Text("$0")
                        .font(.carry.micro)
                        .foregroundColor(Color.textDisabled)
                    Spacer()
                    Text("$1,000")
                        .font(.carry.micro)
                        .foregroundColor(Color.textDisabled)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderLight, lineWidth: 1))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Handicap Allowance Section

    @ViewBuilder
    private var handicapAllowanceSection: some View {
        if selectedCourse != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Handicap Allowance")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                    Spacer()
                    Text("\(Int(handicapPct * 100))%")
                        .font(.carry.captionLGSemibold)
                        .foregroundColor(Color.textPrimary)
                }
                Slider(value: $handicapPct, in: 0.1...1.0, step: 0.05)
                    .tint(Color.textPrimary)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Player Groups Section

    private var playerGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with stepper
            HStack {
                Text("Player Groups")
                    .font(.carry.bodySMBold)
                    .foregroundColor(Color.textPrimary)
                Spacer()
                groupStepper
            }
            .padding(.leading, 4)

            // Group cards
            ForEach(0..<groupCount, id: \.self) { groupIndex in
                groupCard(groupIndex: groupIndex)
            }

            // "+ Add Group" button
            if groupCount < 4 {
                addGroupButton(label: "+ Add Group")
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private func addGroupButton(label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                groupCount = min(4, groupCount + 1)
            }
        } label: {
            Text(label)
                .font(.carry.bodySMBold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.textPrimary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groupStepper: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    groupCount = max(1, groupCount - 1)
                }
            } label: {
                Text("\u{2014}")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(groupCount > 1 ? Color.textPrimary : Color.textDisabled)
                    .frame(width: 32, height: 28)
            }
            .disabled(groupCount <= 1)

            Text("\(groupCount)")
                .font(.carry.headline)
                .foregroundColor(Color.textPrimary)
                .frame(width: 24)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    groupCount = min(4, groupCount + 1)
                }
            } label: {
                Text("+")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(groupCount < 4 ? Color.textPrimary : Color.textDisabled)
                    .frame(width: 32, height: 28)
            }
            .disabled(groupCount >= 4)
        }
    }

    // MARK: - Group Card

    private func groupCard(groupIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if groupCount > 1 {
                Text("GROUP \(groupIndex + 1)")
                    .font(.carry.captionSemibold)
                    .foregroundColor(Color.textDisabled)
                    .padding(.leading, 4)
                    .padding(.bottom, 6)
            }

            VStack(alignment: .leading, spacing: 20) {
                // Score Keeper section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Score Keeper")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)

                    if groupIndex == 0 {
                        scorerConfirmedCreatorRow(groupIndex: 0)
                            .id("slot-0-0")
                    } else {
                        scorerSlotView(groupIndex: groupIndex)
                            .id("slot-\(groupIndex)-0")
                    }
                }

                // Players section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Players")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                        Spacer()
                        Text("Index")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                            .padding(.trailing, 4)
                    }

                    VStack(spacing: 20) {
                        ForEach(1..<4, id: \.self) { slotIndex in
                            playerSlotRow(groupIndex: groupIndex, slotIndex: slotIndex, isReadOnly: false)
                                .id("slot-\(groupIndex)-\(slotIndex)")
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

    // MARK: - Regular Player Slot Row

    private func playerSlotRow(groupIndex: Int, slotIndex: Int, isReadOnly: Bool) -> some View {
        let isNameFocused = focusedField == .name(group: groupIndex, slot: slotIndex)
        let isHCFocused = focusedField == .handicap(group: groupIndex, slot: slotIndex)
        let slot = slots[groupIndex][slotIndex]
        let isCarryUser = slot.existingProfileId != nil && !slot.isPendingInvite
        let showResults = activePlayerSearchSlot?.group == groupIndex
            && activePlayerSearchSlot?.slot == slotIndex
            && !playerSearchResults.isEmpty

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Name field (with optional avatar for Carry users)
                HStack(spacing: 8) {
                    if isCarryUser {
                        PlayerAvatar(player: playerFromSlot(slot), size: 28)
                    }

                    TextField("Enter name", text: nameBinding(groupIndex: groupIndex, slotIndex: slotIndex))
                        .font(.carry.bodyLG)
                        .foregroundColor(Color.textPrimary)
                        .focused($focusedField, equals: .name(group: groupIndex, slot: slotIndex))
                        .disabled(isReadOnly || isCarryUser)
                        .onChange(of: slots[groupIndex][slotIndex].name) { _, newValue in
                            if isNameFocused && !isCarryUser {
                                debouncePlayerSearch(query: newValue, groupIndex: groupIndex, slotIndex: slotIndex)
                            }
                        }

                    if isCarryUser {
                        Button {
                            clearPlayerSlot(groupIndex: groupIndex, slotIndex: slotIndex)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color.textDisabled)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, isCarryUser ? 12 : 21)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isNameFocused ? Color(hexString: "#333333") : Color.borderLight,
                            lineWidth: isNameFocused ? 1.5 : 1
                        )
                )

                // HC field
                TextField("HC", text: handicapBinding(groupIndex: groupIndex, slotIndex: slotIndex))
                    .font(.carry.bodyLG)
                    .foregroundColor(Color.textPrimary)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($focusedField, equals: .handicap(group: groupIndex, slot: slotIndex))
                    .disabled(isReadOnly || isCarryUser)
                    .padding(.horizontal, 6)
                    .frame(width: 56, height: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isHCFocused ? Color(hexString: "#333333") : Color.borderLight,
                                lineWidth: isHCFocused ? 1.5 : 1
                            )
                    )
            }

            // Typeahead results (floating overlay)
            if showResults {
                playerTypeaheadOverlay(groupIndex: groupIndex, slotIndex: slotIndex)
            }
        }
        .zIndex(showResults ? 10 : 0)
    }

    @ViewBuilder
    private func playerTypeaheadOverlay(groupIndex: Int, slotIndex: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(playerSearchResults.prefix(3)) { profile in
                Button {
                    selectPlayerFromSearch(profile: profile, groupIndex: groupIndex, slotIndex: slotIndex)
                } label: {
                    HStack(spacing: 8) {
                        PlayerAvatar(player: playerFromProfile(profile), size: 28)

                        Text(profile.displayName)
                            .font(.carry.bodySemibold)
                            .foregroundColor(Color.textPrimary)

                        if profile.handicap != 0 {
                            Text(String(format: "%.1f", profile.handicap))
                                .font(.carry.bodySM)
                                .foregroundColor(Color.textTertiary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
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

    // MARK: - Scorer Slot (Groups 2+)

    // MARK: - Scorer Slot (Groups 2+)

    private func scorerSlotView(groupIndex: Int) -> some View {
        let slot = slots[groupIndex][0]
        let hasScorer = slot.existingProfileId != nil && !slot.isPendingInvite

        return VStack(spacing: 5) {
            if hasScorer {
                scorerConfirmedRow(slot: slot, groupIndex: groupIndex)
            } else if slot.isPendingInvite {
                scorerInvitedRow(slot: slot, groupIndex: groupIndex)
            } else {
                scorerSearchField(groupIndex: groupIndex)
            }
        }
    }

    /// Group 1: creator auto-filled as scorer
    private func scorerConfirmedCreatorRow(groupIndex: Int) -> some View {
        let slot = slots[groupIndex][0]
        return HStack(spacing: 6) {
            PlayerAvatar(player: playerFromSlot(slot), size: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(slot.name)
                    .font(.carry.bodySMSemibold)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                if !slot.handicap.isEmpty {
                    Text(slot.handicap)
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

    /// Carry user selected as scorer
    private func scorerConfirmedRow(slot: PlayerSlot, groupIndex: Int) -> some View {
        HStack(spacing: 6) {
            PlayerAvatar(player: playerFromSlot(slot), size: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(slot.name)
                    .font(.carry.bodySMSemibold)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                if !slot.handicap.isEmpty {
                    Text(slot.handicap)
                        .font(.carry.bodySM)
                        .foregroundColor(Color(hexString: "#BFC0C2"))
                }
            }

            Spacer()

            Button {
                clearScorer(groupIndex: groupIndex)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.textDisabled)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(height: 58)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight, lineWidth: 1))
    }

    /// SMS-invited scorer (pending)
    private func scorerInvitedRow(slot: PlayerSlot, groupIndex: Int) -> some View {
        HStack(spacing: 6) {
            PlayerAvatar(player: playerFromSlot(slot), size: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(slot.name)
                    .font(.carry.bodySMSemibold)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                if let phone = slot.phoneNumber {
                    Text(phone)
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textPrimary)
                }
            }

            Spacer()

            // "Invited" badge
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

    /// Search field + results/invite cards
    private func scorerSearchField(groupIndex: Int) -> some View {
        VStack(spacing: 5) {
            // Search input
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(Color.textDisabled)

                TextField("Search by name or Invite", text: $scorerSearchText)
                    .font(.carry.bodyLG)
                    .foregroundColor(Color.textPrimary)
                    .focused($focusedField, equals: .scorerSearch(group: groupIndex))
                    .onChange(of: scorerSearchText) { _, newValue in
                        scorerSearchGroupIndex = groupIndex
                        showInlinePhoneEntry = false
                        debounceScorerSearch(query: newValue)
                    }

                if !scorerSearchText.isEmpty {
                    Button {
                        scorerSearchText = ""
                        scorerSearchResults = []
                        showInlinePhoneEntry = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color.textDisabled)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        focusedField == .scorerSearch(group: groupIndex) ? Color(hexString: "#333333") : Color.borderLight,
                        lineWidth: focusedField == .scorerSearch(group: groupIndex) ? 1.5 : 1
                    )
            )

            // Results or invite card
            if scorerSearchGroupIndex == groupIndex {
                scorerResultsCards(groupIndex: groupIndex)
            }
        }
    }

    @ViewBuilder
    private func scorerResultsCards(groupIndex: Int) -> some View {
        let hasResults = !scorerSearchResults.isEmpty
        let showInviteOption = scorerSearchText.count >= 2 && !isScorerSearching

        // Carry user results
        if hasResults {
            ForEach(scorerSearchResults.prefix(5)) { profile in
                Button {
                    selectScorer(profile: profile, groupIndex: groupIndex)
                } label: {
                    HStack(spacing: 10) {
                        PlayerAvatar(player: playerFromProfile(profile), size: 34)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName)
                                .font(.carry.bodySemibold)
                                .foregroundColor(Color.textPrimary)
                            if profile.handicap != 0 {
                                Text(String(format: "%.1f", profile.handicap))
                                    .font(.carry.bodySM)
                                    .foregroundColor(Color(hexString: "#BFC0C2"))
                            }
                        }

                        Spacer()

                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color.textDisabled)
                            .opacity(0) // placeholder for alignment
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

        // Inline SMS invite with phone input
        if showInviteOption {
            VStack(alignment: .leading, spacing: 12) {
                Text("Send Invite to \"\(scorerSearchText)\"")
                    .font(.carry.bodySMSemibold)
                    .foregroundColor(Color.textTertiary)

                HStack(spacing: 10) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.textDisabled)

                    TextField("Enter Phone Number", text: $inlinePhoneText)
                        .font(.carry.bodyLG)
                        .foregroundColor(Color.textPrimary)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .inlinePhone(group: groupIndex))
                        .onAppear {
                            inlinePhoneName = scorerSearchText
                            inlinePhoneText = ""
                        }

                    let digits = inlinePhoneText.filter { $0.isNumber }
                    Button {
                        sendInlineInvite(groupIndex: groupIndex)
                    } label: {
                        Text("Send")
                            .font(.carry.bodySMSemibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(Capsule().fill(digits.count >= 10 ? Color.successGreen : Color.borderSubtle))
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

    // MARK: - Scorer Search

    private func debounceScorerSearch(query: String) {
        scorerSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            scorerSearchResults = []
            return
        }
        isScorerSearching = true
        scorerSearchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do {
                let results = try await PlayerSearchService.shared.searchPlayers(query: trimmed)
                // Filter out creator and already-selected scorers
                var usedIds = Set(slots.compactMap { $0[0].existingProfileId })
                if let creatorId = currentUser.profileId {
                    usedIds.insert(creatorId)
                }
                let filtered = results.filter { !usedIds.contains($0.id) }
                await MainActor.run {
                    scorerSearchResults = filtered
                    isScorerSearching = false
                }
            } catch {
                await MainActor.run {
                    scorerSearchResults = []
                    isScorerSearching = false
                }
            }
        }
    }

    private func selectScorer(profile: ProfileDTO, groupIndex: Int) {
        slots[groupIndex][0] = PlayerSlot(
            name: profile.displayName,
            handicap: String(format: "%.1f", profile.handicap),
            existingProfileId: profile.id,
            color: profile.color
        )
        scorerSearchText = ""
        scorerSearchResults = []
        scorerSearchGroupIndex = nil
        focusedField = nil
    }

    private func sendInlineInvite(groupIndex: Int) {
        let digits = inlinePhoneText.filter { $0.isNumber }
        guard digits.count >= 10 else { return }

        let name = inlinePhoneName.trimmingCharacters(in: .whitespaces)

        slots[groupIndex][0] = PlayerSlot(
            name: name.isEmpty ? formatPhoneDisplay(digits) : name,
            isPendingInvite: true,
            phoneNumber: digits
        )
        slots[groupIndex][0].color = slotColors[(groupIndex * 4) % slotColors.count]

        // Open native SMS with invite link
        let body = "Score our skins game on Carry! Download: https://carryapp.site"
        let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "sms:\(digits)&body=\(encoded)") {
            UIApplication.shared.open(url)
        }

        // Reset all search state
        scorerSearchText = ""
        scorerSearchResults = []
        scorerSearchGroupIndex = nil
        showInlinePhoneEntry = false
        inlinePhoneText = ""
        inlinePhoneName = ""
        focusedField = nil
    }

    private func formatPhoneDisplay(_ digits: String) -> String {
        guard digits.count >= 10 else { return digits }
        let last10 = String(digits.suffix(10))
        let area = last10.prefix(3)
        let mid = last10.dropFirst(3).prefix(3)
        let end = last10.suffix(4)
        return "(\(area)) \(mid)-\(end)"
    }

    private func clearScorer(groupIndex: Int) {
        slots[groupIndex][0] = PlayerSlot(
            color: slotColors[(groupIndex * 4) % slotColors.count]
        )
        scorerSearchText = ""
        scorerSearchResults = []
        showInlinePhoneEntry = false
        inlinePhoneText = ""
        inlinePhoneName = ""
    }

    // MARK: - Player Name Typeahead

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
                // Filter out creator, already-selected scorers, and already-added players
                var usedIds = Set(slots.prefix(groupCount).joined().compactMap { $0.existingProfileId })
                if let creatorId = currentUser.profileId {
                    usedIds.insert(creatorId)
                }
                let filtered = results.filter { !usedIds.contains($0.id) }
                await MainActor.run {
                    playerSearchResults = filtered
                    if filtered.isEmpty {
                        activePlayerSearchSlot = nil
                    }
                }
            } catch {
                await MainActor.run {
                    playerSearchResults = []
                    activePlayerSearchSlot = nil
                }
            }
        }
    }

    private func selectPlayerFromSearch(profile: ProfileDTO, groupIndex: Int, slotIndex: Int) {
        slots[groupIndex][slotIndex] = PlayerSlot(
            name: profile.displayName,
            handicap: String(format: "%.1f", profile.handicap),
            existingProfileId: profile.id,
            color: profile.color
        )
        playerSearchResults = []
        activePlayerSearchSlot = nil
        focusedField = nil
    }

    private func clearPlayerSlot(groupIndex: Int, slotIndex: Int) {
        slots[groupIndex][slotIndex] = PlayerSlot(
            color: slotColors[(groupIndex * 4 + slotIndex) % slotColors.count]
        )
        playerSearchResults = []
        activePlayerSearchSlot = nil
    }

    // MARK: - Helpers (Slot/Profile → Player for PlayerAvatar)

    private func playerFromSlot(_ slot: PlayerSlot) -> Player {
        Player(
            id: Player.stableId(from: slot.existingProfileId ?? slot.id),
            name: slot.name,
            initials: slot.initials,
            color: slot.color,
            handicap: Double(slot.handicap) ?? 0,
            avatar: "",
            group: 1,
            ghinNumber: nil,
            venmoUsername: nil,
            isPendingInvite: slot.isPendingInvite,
            profileId: slot.existingProfileId
        )
    }

    private func playerFromProfile(_ profile: ProfileDTO) -> Player {
        Player(from: profile)
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        VStack(spacing: 0) {
            Button {
                if !isFormValid {
                    ToastManager.shared.error(continueHint)
                } else {
                    createQuickGame()
                }
            } label: {
                Group {
                    if isCreating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Continue")
                            .font(.carry.headline)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isFormValid && !isCreating ? Color.textPrimary : Color.borderSubtle)
                )
            }
            .disabled(isCreating)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 2)

            // Hint text for what's missing
            if !isFormValid {
                Text(continueHint)
                    .font(.carry.caption)
                    .foregroundColor(Color.textTertiary)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
        }
        .background(Color.white)
    }

    private var continueHint: String {
        if selectedCourse == nil { return "Select a course to continue" }
        if filledPlayerCount < 2 { return "Add at least 2 players" }
        if let name = firstPlayerMissingHandicap { return "Missing HC index for \(name)" }
        return ""
    }

    private var firstPlayerMissingHandicap: String? {
        for g in 0..<groupCount {
            for slot in slots[g] where !slot.isEmpty {
                if slot.handicap.trimmingCharacters(in: .whitespaces).isEmpty {
                    return slot.name
                }
            }
        }
        return nil
    }

    // MARK: - Bindings

    private func nameBinding(groupIndex: Int, slotIndex: Int) -> Binding<String> {
        Binding(
            get: { slots[groupIndex][slotIndex].name },
            set: { newValue in
                slots[groupIndex][slotIndex].name = newValue
                if !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    let colorIndex = (groupIndex * 4 + slotIndex) % slotColors.count
                    slots[groupIndex][slotIndex].color = slotColors[colorIndex]
                }
            }
        )
    }

    private func handicapBinding(groupIndex: Int, slotIndex: Int) -> Binding<String> {
        Binding(
            get: { slots[groupIndex][slotIndex].handicap },
            set: { newValue in
                slots[groupIndex][slotIndex].handicap = filterHandicap(newValue)
            }
        )
    }

    /// Matches OnboardingView/GroupManagerView handicap filter:
    /// +handicap up to +10.0, regular up to 54.0, one decimal place max.
    private func filterHandicap(_ input: String) -> String {
        var filtered = ""
        var hasDecimal = false
        var hasPlus = false
        var decimalDigits = 0
        for ch in input {
            if ch == "+" && filtered.isEmpty && !hasPlus {
                hasPlus = true
                filtered.append(ch)
            } else if (ch == "." || ch == ",") && !hasDecimal {
                hasDecimal = true
                filtered.append(".")
            } else if ch.isNumber {
                if hasDecimal {
                    guard decimalDigits < 1 else { continue }
                    filtered.append(ch)
                    decimalDigits += 1
                } else {
                    let wholeDigits = filtered.filter { $0.isNumber }.count
                    guard wholeDigits < 2 else { continue }
                    filtered.append(ch)
                }
            }
        }
        let numericStr = filtered.hasPrefix("+") ? String(filtered.dropFirst()) : filtered
        if let value = Double(numericStr) {
            if hasPlus && value > 10.0 { filtered = "+10.0" }
            else if !hasPlus && value > 54.0 { filtered = "54.0" }
        }
        return filtered
    }

    // MARK: - Create Quick Game

    private func createQuickGame() {
        focusedField = nil
        isCreating = true

        // Build players from filled slots
        var players: [Player] = []
        for groupIndex in 0..<groupCount {
            for slotIndex in 0..<4 {
                let slot = slots[groupIndex][slotIndex]
                guard !slot.isEmpty else { continue }

                let handicapValue = Double(slot.handicap) ?? 0
                let playerId: Int
                let profileId: UUID?

                if let existingId = slot.existingProfileId {
                    playerId = Player.stableId(from: existingId)
                    profileId = existingId
                } else {
                    playerId = Player.stableId(from: slot.id)
                    profileId = nil
                }

                let player = Player(
                    id: playerId,
                    name: slot.name.trimmingCharacters(in: .whitespaces),
                    initials: slot.initials,
                    color: slot.color,
                    handicap: handicapValue,
                    avatar: "",
                    group: groupIndex + 1,
                    ghinNumber: nil,
                    venmoUsername: nil,
                    avatarImageName: nil,
                    avatarUrl: nil,
                    phoneNumber: slot.phoneNumber,
                    isPendingInvite: slot.isPendingInvite,
                    isGuest: slot.existingProfileId == nil && !slot.isPendingInvite,
                    profileId: profileId
                )
                players.append(player)
            }
        }

        // Build tee times array for groups
        var teeTimes: [Date?] = []
        if hasTeeTime {
            for i in 0..<groupCount {
                let offset = Double(i) * Double(consecutiveInterval) * 60
                teeTimes.append(teeTimeDate.addingTimeInterval(offset))
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, MMM d"
        let autoName = dateFormatter.string(from: hasTeeTime ? teeTimeDate : Date())

        let creatorIntId = Player.stableId(from: currentUser.profileId ?? UUID())

        let savedGroup = SavedGroup(
            id: UUID(), // Temporary — will be replaced by Supabase ID
            name: autoName,
            members: players,
            lastPlayed: nil,
            creatorId: creatorIntId,
            lastCourse: selectedCourse,
            activeRound: nil,
            roundHistory: [],
            potSize: buyInAmount * Double(players.count),
            buyInPerPlayer: buyInAmount,
            scheduledDate: hasTeeTime ? teeTimeDate : nil,
            handicapPercentage: handicapPct,
            isQuickGame: true,
            teeTimes: teeTimes.isEmpty ? nil : teeTimes,
            teeTimeInterval: consecutiveInterval > 0 ? consecutiveInterval : nil
        )

        isCreating = false
        onCreate(savedGroup)
    }
}
