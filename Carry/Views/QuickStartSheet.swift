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
    var homeClub: String? = nil

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
    @EnvironmentObject var storeService: StoreService
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
    @State private var showHCPicker = false
    @State private var hcPickerValue: Double = 0
    @State private var hcPickerIsPlus: Bool = false
    @State private var hcPickerGroupIndex: Int = 0
    @State private var hcPickerSlotIndex: Int = 0
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

    // Scorer search state — now handled by ScorerAssignmentView

    // Player name typeahead state
    @State private var playerSearchResults: [ProfileDTO] = []
    @State private var playerSearchTask: Task<Void, Never>?
    @State private var activePlayerSearchSlot: (group: Int, slot: Int)? = nil

    @FocusState private var focusedField: SlotField?

    @Environment(\.dismiss) private var dismiss

    private enum SlotField: Hashable {
        case name(group: Int, slot: Int)
        case handicap(group: Int, slot: Int)
    }

    // MARK: - Computed

    private var filledPlayerCount: Int {
        slots.prefix(groupCount).joined().filter { !$0.isEmpty }.count
    }

    private var isFormValid: Bool {
        // Course must be set AND have full per-hole data
        guard let course = selectedCourse,
              let holes = course.teeBox?.holes,
              holes.count == 18 else { return false }
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
                // SMS invites don't have HC yet — skip them
                if slot.isPendingInvite { continue }
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
                    slot.homeClub = currentUser.homeClub
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
                    handicapAllowanceSection
                    teeTimeSection
                    buyInSection
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
                    case .name(let group, let slot):
                        scrollProxy.scrollTo("slot-\(group)-\(slot)", anchor: .center)
                    case .handicap:
                        break // HC uses picker sheet, not keyboard focus
                    }
                }
            }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .onTapGesture { focusedField = nil }
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
        .sheet(isPresented: $showHCPicker) {
            HandicapPickerSheet(
                handicap: $hcPickerValue,
                isPlus: $hcPickerIsPlus
            )
            .presentationDetents([.height(520)])
            .presentationDragIndicator(.visible)
            .onDisappear {
                let absVal = abs(hcPickerValue)
                if hcPickerIsPlus || hcPickerValue < 0 {
                    slots[hcPickerGroupIndex][hcPickerSlotIndex].handicap = "+\(String(format: "%.1f", absVal))"
                } else {
                    slots[hcPickerGroupIndex][hcPickerSlotIndex].handicap = String(format: "%.1f", absVal)
                }
            }
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
        // Course — only prefill if the saved course has real per-hole data.
        // Otherwise force the user to re-pick (which goes through CourseSelectionView's
        // strict tee filter and guarantees full hole data).
        if let course = game.lastCourse,
           let holes = course.teeBox?.holes,
           holes.count == 18 {
            selectedCourse = course
        } else {
            selectedCourse = nil
        }

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
                        slot.homeClub = currentUser.homeClub
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
                        slot.homeClub = player.homeClub
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
                    if !storeService.isPremium {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.textDisabled)
                    }
                    Spacer()
                    Text("\(Int(handicapPct * 100))%")
                        .font(.carry.captionLGSemibold)
                        .foregroundColor(Color.textPrimary)
                }
                if !storeService.isPremium {
                    HStack(spacing: 4) {
                        Image("premium-crown")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 11)
                            .foregroundColor(Color.goldDark)
                        Text("Premium feature")
                            .font(.carry.caption)
                            .foregroundColor(Color.textDisabled)
                    }
                }
                Slider(value: $handicapPct, in: 0.1...1.0, step: 0.05)
                    .tint(Color.textPrimary)
                    .disabled(!storeService.isPremium)
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
            if groupCount < 5 {
                addGroupButton(label: "+ Add Group")
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private func removeGroup(at index: Int) {
        guard index > 0, groupCount > 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            // Clear the slots for this group
            slots[index] = (0..<4).map { s in
                PlayerSlot(color: slotColors[(index * 4 + s) % slotColors.count])
            }
            groupCount -= 1
        }
    }

    private func addGroupButton(label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                groupCount = min(5, groupCount + 1)
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
                    groupCount = min(5, groupCount + 1)
                }
            } label: {
                Text("+")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(groupCount < 5 ? Color.textPrimary : Color.textDisabled)
                    .frame(width: 32, height: 28)
            }
            .disabled(groupCount >= 5)
        }
    }

    // MARK: - Group Card

    private func groupCard(groupIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if groupCount > 1 {
                HStack {
                    Text("GROUP \(groupIndex + 1)")
                        .font(.carry.captionSemibold)
                        .foregroundColor(Color.textDisabled)
                    Spacer()
                    if groupIndex > 0 {
                        Button {
                            removeGroup(at: groupIndex)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "minus")
                                    .font(.system(size: 12, weight: .bold))
                                Text("REMOVE")
                                    .font(.carry.captionSemibold)
                            }
                            .foregroundColor(Color.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 4)
                .padding(.bottom, 6)
            }

            VStack(alignment: .leading, spacing: 20) {
                // Score Keeper section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Score Keeper")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)

                    ScorerAssignmentView(
                        scorer: scorerSlotBinding(groupIndex: groupIndex),
                        excludeProfileIds: scorerExcludeIds(forGroup: groupIndex),
                        groupLabel: "Group \(groupIndex + 1)",
                        defaultColor: slotColors[(groupIndex * 4) % slotColors.count],
                        readOnly: groupIndex == 0
                    )
                    .id("slot-\(groupIndex)-0")
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
        // HC uses picker sheet — no focus state needed
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

                        VStack(alignment: .leading, spacing: 1) {
                            Text(slot.name)
                                .font(.carry.bodySemibold)
                                .foregroundColor(Color.textPrimary)
                                .lineLimit(1)
                            let subtitle = [slot.homeClub, !slot.handicap.isEmpty ? slot.handicap : nil]
                                .compactMap { $0 }.joined(separator: " · ")
                            if !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.carry.caption)
                                    .foregroundColor(Color(hexString: "#BFC0C2"))
                            }
                        }

                        Spacer()

                        Button {
                            clearPlayerSlot(groupIndex: groupIndex, slotIndex: slotIndex)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color.textDisabled)
                        }
                        .buttonStyle(.plain)
                    } else {
                        TextField("Enter name", text: nameBinding(groupIndex: groupIndex, slotIndex: slotIndex))
                            .font(.carry.bodyLG)
                            .foregroundColor(Color.textPrimary)
                            .focused($focusedField, equals: .name(group: groupIndex, slot: slotIndex))
                            .disabled(isReadOnly)
                            .onChange(of: slots[groupIndex][slotIndex].name) { _, newValue in
                                // Check focus live (not the captured let) so search triggers on typing
                                if focusedField == .name(group: groupIndex, slot: slotIndex) {
                                    debouncePlayerSearch(query: newValue, groupIndex: groupIndex, slotIndex: slotIndex)
                                }
                            }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 58)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isNameFocused ? Color(hexString: "#333333") : Color.borderLight,
                            lineWidth: isNameFocused ? 1.5 : 1
                        )
                )

                // HC field — tappable to open picker
                Button {
                    guard !isReadOnly, !isCarryUser else { return }
                    focusedField = nil
                    let hcStr = slots[groupIndex][slotIndex].handicap
                    let val: Double = hcStr.hasPrefix("+") ? -(Double(String(hcStr.dropFirst())) ?? 0) : Double(hcStr) ?? 0
                    hcPickerValue = val
                    hcPickerIsPlus = val < 0
                    hcPickerGroupIndex = groupIndex
                    hcPickerSlotIndex = slotIndex
                    showHCPicker = true
                } label: {
                    let hcStr = slots[groupIndex][slotIndex].handicap
                    Text(hcStr.isEmpty ? "HC" : hcStr)
                        .font(.carry.bodyLG)
                        .foregroundColor(hcStr.isEmpty ? Color.textDisabled : Color.textPrimary)
                        .frame(width: 56, height: 50)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isReadOnly || isCarryUser)
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
                    HStack(spacing: 10) {
                        PlayerAvatar(player: playerFromProfile(profile), size: 34)

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

    // MARK: - Scorer UI — handled by ScorerAssignmentView

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
            name: "\(profile.firstName) \(profile.lastName)".trimmingCharacters(in: .whitespaces),
            handicap: String(format: "%.1f", profile.handicap),
            existingProfileId: profile.id,
            color: profile.color,
            homeClub: profile.homeClub
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
        if let group = firstGroupMissingScorer { return "Assign a scorer for Group \(group)" }
        if let name = firstPlayerMissingHandicap { return "Missing HC index for \(name)" }
        return ""
    }

    private var firstGroupMissingScorer: Int? {
        for g in 0..<groupCount {
            let hasPlayers = slots[g].contains { !$0.isEmpty }
            if hasPlayers && slots[g][0].existingProfileId == nil && !slots[g][0].isPendingInvite {
                return g + 1
            }
        }
        return nil
    }

    private var firstPlayerMissingHandicap: String? {
        for g in 0..<groupCount {
            for slot in slots[g] where !slot.isEmpty {
                // SMS invites can't provide HC — skip validation for them
                if slot.isPendingInvite { continue }
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

    // HC binding removed — uses HandicapPickerSheet instead

    /// Matches OnboardingView/GroupManagerView handicap filter:
    /// +handicap up to +10.0, regular up to 54.0, one decimal place max.
    // Uses shared filterHandicapInput() from Player.swift

    // MARK: - Scorer Assignment Bindings

    /// Bridges ScorerSlot ↔ PlayerSlot for ScorerAssignmentView
    private func scorerSlotBinding(groupIndex: Int) -> Binding<ScorerSlot> {
        Binding(
            get: {
                let slot = slots[groupIndex][0]
                return ScorerSlot(
                    name: slot.name,
                    handicap: slot.handicap,
                    profileId: slot.existingProfileId,
                    color: slot.color,
                    isPendingInvite: slot.isPendingInvite,
                    phoneNumber: slot.phoneNumber,
                    homeClub: slot.homeClub
                )
            },
            set: { newValue in
                slots[groupIndex][0] = PlayerSlot(
                    name: newValue.name,
                    handicap: newValue.handicap,
                    existingProfileId: newValue.profileId,
                    color: newValue.color.isEmpty ? slotColors[(groupIndex * 4) % slotColors.count] : newValue.color,
                    isPendingInvite: newValue.isPendingInvite,
                    phoneNumber: newValue.phoneNumber
                )
            }
        )
    }

    /// Profile IDs to exclude from scorer search (creator + already-assigned scorers)
    private func scorerExcludeIds(forGroup groupIndex: Int) -> Set<UUID> {
        var ids = Set<UUID>()
        if let creatorId = currentUser.profileId {
            ids.insert(creatorId)
        }
        for g in 0..<groupCount where g != groupIndex {
            if let pid = slots[g][0].existingProfileId {
                ids.insert(pid)
            }
        }
        return ids
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

                let handicapValue: Double = {
                    if slot.handicap.hasPrefix("+") {
                        return -(Double(String(slot.handicap.dropFirst())) ?? 0.0)
                    }
                    return Double(slot.handicap) ?? 0.0
                }()
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
