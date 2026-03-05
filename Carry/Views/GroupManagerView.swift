import SwiftUI

/// Identifiable wrapper for item-based sheets (avoids stale state with .sheet(isPresented:))
private struct SheetItem: Identifiable {
    let id: Int
}

struct GroupManagerView: View {
    let allMembers: [Player]
    @State private var selectedIDs: Set<Int>
    @State private var groups: [[Player]]
    @State private var startingSides: [String]  // "front" or "back" per group
    @State private var dragPlayer: Player?
    @State private var dragSourceGroup: Int?
    @State private var dropTargetGroup: Int?
    @State private var dropTargetIndex: Int?  // target row index for within-group reorder
    @State private var showAddSheet = false
    @State private var showGuestEntry = false
    @State private var guestName = ""
    @State private var guestHandicap = ""
    @State private var guests: [Player] = []
    @State private var nextGuestID = 100  // IDs above real players
    @State private var showTeeTimes = true  // off by default, toggled in settings
    @State private var teeTimes: [Date?] = []  // one per group, nil = not set
    @State private var showSettings = false
    @State private var showLeaderboard = false
    @State private var groupName = "Friday Meetings"  // editable group/event name
    @State private var showSwapPicker = false
    @State private var pendingSwapPlayer: Player?   // player being moved
    @State private var pendingSwapFrom: Int?         // source group index
    @State private var pendingSwapTo: Int?           // destination group index (full)
    @State private var scorerIDs: [Int]              // one scorer player ID per group
    @State private var showTeeTimePicker = false
    @State private var teeTimePickerGroupIndex: Int = 0
    @State private var teeTimePickerDate: Date = Date()
    @State private var scorerPickerItem: SheetItem? = nil  // nil = hidden; .id = group index
    @State private var showNameEditor = false
    @State private var editingName = ""
    @State private var teeTimesLinked = false  // true when times are set at consecutive intervals
    @State private var selectedTees: [String]  // tee color per group (e.g. "Combos", "Blues")
    @State private var carriesEnabled = false  // carries toggle (off by default for multi-group)

    private let teeTimeInterval: TimeInterval = 8 * 60  // 8 minutes between groups
    private let teeOptions = ["Combos", "Blues", "White", "Gold", "Red"]

    var onBack: (() -> Void)?
    let onConfirm: (RoundConfig) -> Void

    init(allMembers: [Player], preselected: Set<Int>? = nil, onBack: (() -> Void)? = nil, onConfirm: @escaping (RoundConfig) -> Void) {
        self.allMembers = allMembers
        self.onBack = onBack
        self.onConfirm = onConfirm
        let sel = preselected ?? Set(allMembers.map(\.id))
        _selectedIDs = State(initialValue: sel)
        let playing = allMembers.filter { sel.contains($0.id) }
        let grouped = Self.autoGroup(playing)
        _groups = State(initialValue: grouped)
        _startingSides = State(initialValue: Self.defaultSides(count: grouped.count))
        _teeTimes = State(initialValue: Array(repeating: nil, count: grouped.count))
        _scorerIDs = State(initialValue: grouped.map { $0.first?.id ?? 0 })
        _selectedTees = State(initialValue: Array(repeating: "Combos", count: grouped.count))
    }

    // MARK: - Auto-grouping

    /// Splits players into balanced groups of 3-4 (foursomes preferred).
    /// 5→3+2, 6→3+3, 7→4+3, 8→4+4, 9→3+3+3, 10→4+3+3, 11→4+4+3, 12→4+4+4, etc.
    static func autoGroup(_ players: [Player]) -> [[Player]] {
        let n = players.count
        guard n > 0 else { return [] }
        if n <= 4 { return [players] }

        let numGroups = (n + 3) / 4  // ceil(n/4)
        let baseSize = n / numGroups
        let remainder = n % numGroups

        var result: [[Player]] = []
        var idx = 0
        for g in 0..<numGroups {
            let size = baseSize + (g < remainder ? 1 : 0)
            result.append(Array(players[idx..<idx+size]))
            idx += size
        }
        return result
    }

    static func defaultSides(count: Int) -> [String] {
        // Alternate front/back, first group always front
        (0..<count).map { $0 % 2 == 0 ? "front" : "back" }
    }

    private var allAvailable: [Player] {
        allMembers + guests
    }

    private func regroup() {
        let playing = allAvailable.filter { selectedIDs.contains($0.id) }
        groups = Self.autoGroup(playing)
        startingSides = Self.defaultSides(count: groups.count)
        syncTeeTimes()
        syncScorerIDs()
        syncSelectedTees()
    }

    private func syncTeeTimes() {
        while teeTimes.count < groups.count {
            teeTimes.append(nil)
        }
        while teeTimes.count > groups.count {
            teeTimes.removeLast()
        }
    }

    /// Ensure each group has a valid scorer; default to first player if missing or invalid
    private func syncScorerIDs() {
        while scorerIDs.count < groups.count {
            scorerIDs.append(groups[scorerIDs.count].first?.id ?? 0)
        }
        while scorerIDs.count > groups.count {
            scorerIDs.removeLast()
        }
        // Validate: if scorer was moved out of group, reassign to first player
        for i in 0..<groups.count {
            let groupPlayerIDs = Set(groups[i].map(\.id))
            if !groupPlayerIDs.contains(scorerIDs[i]) {
                scorerIDs[i] = groups[i].first?.id ?? 0
            }
        }
    }

    /// Ensure each group has a selected tee; default to "Combos"
    private func syncSelectedTees() {
        while selectedTees.count < groups.count {
            selectedTees.append("Combos")
        }
        while selectedTees.count > groups.count {
            selectedTees.removeLast()
        }
    }

    /// When the first group's tee time is set, auto-fill subsequent groups at 8-min intervals
    private func autoFillTeeTimes(from index: Int) {
        guard let baseTime = teeTimes[index] else { return }
        for i in (index + 1)..<teeTimes.count {
            let offset = Double(i - index) * teeTimeInterval
            teeTimes[i] = baseTime.addingTimeInterval(offset)
        }
    }

    private static let teeTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private var selectedCount: Int { selectedIDs.count }

    var body: some View {
        ZStack {
            Color(hex: "#F0F0F0").ignoresSafeArea()

            VStack(spacing: 0) {
                // Floating header: Back + Group name + settings button
                HStack(spacing: 12) {
                    if let onBack {
                        Button {
                            onBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "#1A1A1A"))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(.white))
                                .clipShape(Circle())
                        }
                    }

                    Button {
                        editingName = groupName
                        showNameEditor = true
                    } label: {
                        Text(groupName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(spacing: 10) {
                        // Leaderboard button
                        Button {
                            showLeaderboard = true
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(Color(hex: "#1A1A1A"), lineWidth: 1.5)
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "#1A1A1A"))
                            }
                            .frame(width: 36, height: 36)
                        }

                        // Settings button
                        Button {
                            showSettings = true
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(Color(hex: "#1A1A1A"), lineWidth: 1.5)
                                Image(systemName: "gearshape")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(hex: "#1A1A1A"))
                            }
                            .frame(width: 36, height: 36)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)
                .background(Color(hex: "#F0F0F0"))

                ScrollView {
                VStack(spacing: 0) {
                    // Who's playing header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Who's playing?")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                        Text("\(selectedCount) player\(selectedCount == 1 ? "" : "s") selected")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#BBBBBB"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // Player grid — add button first, then player chips
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        // Add button as first item
                        addPlayerChip

                        ForEach(allAvailable) { player in
                            playerChip(player)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Divider
                    Rectangle()
                        .fill(Color(hex: "#E0E0E0"))
                        .frame(height: 1)
                        .padding(.vertical, 24)
                        .padding(.horizontal, 20)

                    // Groups section
                    if selectedCount > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Groups")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(hex: "#1A1A1A"))
                            Text("Tap or press to move the group order, or move players between groups.")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#BBBBBB"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                        ForEach(Array(groups.enumerated()), id: \.offset) { groupIdx, group in
                            groupCard(index: groupIdx, players: group)
                                .id(group.map(\.id))  // force re-render when players change
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                        }
                    } else {
                        Text("Select players above to create groups.")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#CCCCCC"))
                            .padding(.top, 20)
                    }

                    Spacer().frame(height: 100)
                }
            }
            } // end floating header VStack

            // Confirm button pinned to bottom
            VStack {
                Spacer()
                Button {
                    let groupConfigs = groups.enumerated().map { idx, players in
                        GroupConfig(id: idx + 1, startingSide: startingSides[idx], playerIDs: players.map(\.id))
                    }
                    let config = RoundConfig(
                        id: UUID().uuidString,
                        number: 1,
                        course: "Blackhawk CC",
                        date: ISO8601DateFormatter().string(from: Date()),
                        buyIn: 50,
                        gameType: "skins",
                        skinRules: SkinRules(net: true, carries: carriesEnabled, outright: true, handicapPercentage: 1.0),
                        teeBox: TeeBox.demo[1],
                        groups: groupConfigs,
                        creatorId: 1  // TODO: derive from AuthService when auth is live
                    )
                    onConfirm(config)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Start Round")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedCount >= 2
                                  ? Color(hex: "#1A1A1A")
                                  : Color(hex: "#CCCCCC"))
                    )
                }
                .disabled(selectedCount < 2)
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addPlayerSheet
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGuestEntry) {
            guestEntrySheet
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLeaderboard) {
            leaderboardSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSwapPicker) {
            swapPickerSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTeeTimePicker) {
            teeTimePickerSheet
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $scorerPickerItem) { item in
            scorerPickerSheet(groupIndex: item.id)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Edit Name", isPresented: $showNameEditor) {
            TextField("Group name", text: $editingName)
            Button("Save") {
                let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    groupName = trimmed
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Swap Picker Sheet

    private var swapPickerSheet: some View {
        VStack(spacing: 0) {
            Text("Swap Player")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))
                .padding(.top, 24)
                .padding(.bottom, 6)

            if let player = pendingSwapPlayer, let destIdx = pendingSwapTo {
                Text("Group \(destIdx + 1) is full. Pick a player to swap with \(player.name).")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#999999"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                ForEach(groups[destIdx]) { destPlayer in
                    Button {
                        performSwap(incoming: player, outgoing: destPlayer)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: destPlayer.color).opacity(0.09))
                                Circle()
                                    .strokeBorder(Color(hex: destPlayer.color).opacity(0.25), lineWidth: 1.5)
                                Text(destPlayer.avatar)
                                    .font(.system(size: 16))
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(destPlayer.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color(hex: "#1A1A1A"))
                                Text("HCP \(String(format: "%.1f", destPlayer.handicap))")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "#BBBBBB"))
                            }

                            Spacer()

                            Image(systemName: "arrow.triangle.swap")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "#CCCCCC"))
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if destPlayer.id != groups[destIdx].last?.id {
                        Rectangle()
                            .fill(Color(hex: "#F0F0F0"))
                            .frame(height: 1)
                            .padding(.leading, 72)
                    }
                }
            }

            Spacer()
        }
    }

    private func performSwap(incoming: Player, outgoing: Player) {
        guard let fromIdx = pendingSwapFrom, let toIdx = pendingSwapTo else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            // Remove incoming from source, add outgoing
            groups[fromIdx].removeAll { $0.id == incoming.id }
            groups[fromIdx].append(outgoing)
            // Remove outgoing from dest, add incoming
            groups[toIdx].removeAll { $0.id == outgoing.id }
            groups[toIdx].append(incoming)
            syncScorerIDs()
        }
        // Reset swap state
        showSwapPicker = false
        pendingSwapPlayer = nil
        pendingSwapFrom = nil
        pendingSwapTo = nil
    }

    // MARK: - Tee Time Picker Sheet

    private var teeTimePickerSheet: some View {
        VStack(spacing: 0) {
            Text("Set Tee Time")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))
                .padding(.top, 24)
                .padding(.bottom, 4)

            Text("Group \(teeTimePickerGroupIndex + 1)")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#999999"))
                .padding(.bottom, 20)

            DatePicker(
                "",
                selection: $teeTimePickerDate,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 120)
            .clipped()
            .padding(.horizontal, 40)

            Spacer().frame(height: 24)

            if teeTimesLinked {
                // Linked mode — update all groups maintaining intervals
                Button {
                    teeTimes[teeTimePickerGroupIndex] = teeTimePickerDate
                    for i in 0..<teeTimes.count {
                        if i != teeTimePickerGroupIndex {
                            let offset = Double(i - teeTimePickerGroupIndex) * teeTimeInterval
                            teeTimes[i] = teeTimePickerDate.addingTimeInterval(offset)
                        }
                    }
                    showTeeTimePicker = false
                } label: {
                    Text("Update All Groups")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "#1A1A1A"))
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                Button {
                    teeTimes[teeTimePickerGroupIndex] = teeTimePickerDate
                    teeTimesLinked = false
                    showTeeTimePicker = false
                } label: {
                    Text("Set This Group Only")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(hex: "#E0E0E0"), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 24)

                Text("Groups are linked at 8-min intervals")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#BBBBBB"))
                    .padding(.top, 10)
            } else {
                // Unlinked mode — choose one or all
                Button {
                    teeTimes[teeTimePickerGroupIndex] = teeTimePickerDate
                    showTeeTimePicker = false
                } label: {
                    Text("Set This Group Only")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "#1A1A1A"))
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                Button {
                    teeTimes[teeTimePickerGroupIndex] = teeTimePickerDate
                    for i in 0..<teeTimes.count {
                        if i != teeTimePickerGroupIndex {
                            let offset = Double(i - teeTimePickerGroupIndex) * teeTimeInterval
                            teeTimes[i] = teeTimePickerDate.addingTimeInterval(offset)
                        }
                    }
                    teeTimesLinked = true
                    showTeeTimePicker = false
                } label: {
                    Text("Set All Groups (8-min intervals)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(hex: "#E0E0E0"), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 24)
            }

            Spacer()
        }
    }

    // MARK: - Scorer Picker Sheet

    private func scorerPickerSheet(groupIndex: Int) -> some View {
        VStack(spacing: 0) {
            Text("Assign Scorer")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))
                .padding(.top, 24)
                .padding(.bottom, 6)

            Text("Pick who keeps score for Group \(groupIndex + 1).")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#999999"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            if groupIndex < groups.count {
                ForEach(groups[groupIndex]) { player in
                    let isCurrentScorer = groupIndex < scorerIDs.count && scorerIDs[groupIndex] == player.id

                    Button {
                        scorerIDs[groupIndex] = player.id
                        scorerPickerItem = nil
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: player.color).opacity(0.09))
                                Circle()
                                    .strokeBorder(Color(hex: player.color).opacity(0.25), lineWidth: 1.5)
                                Text(player.avatar)
                                    .font(.system(size: 16))
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color(hex: "#1A1A1A"))
                                Text("HCP \(String(format: "%.1f", player.handicap))")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "#BBBBBB"))
                            }

                            Spacer()

                            if isCurrentScorer {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color(hex: "#1A1A1A"))
                            } else {
                                Circle()
                                    .strokeBorder(Color(hex: "#DDDDDD"), lineWidth: 1.5)
                                    .frame(width: 18, height: 18)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if player.id != groups[groupIndex].last?.id {
                        Rectangle()
                            .fill(Color(hex: "#F0F0F0"))
                            .frame(height: 1)
                            .padding(.leading, 72)
                    }
                }
            }

            Spacer()
        }
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

    // MARK: - Player Chip

    private func playerChip(_ player: Player) -> some View {
        let isSelected = selectedIDs.contains(player.id)

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                if isSelected {
                    selectedIDs.remove(player.id)
                } else {
                    selectedIDs.insert(player.id)
                }
            }
            regroup()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color(hex: player.color).opacity(isSelected ? 0.09 : 0.03))
                    Circle()
                        .strokeBorder(
                            Color(hex: player.color).opacity(isSelected ? 0.3 : 0.1),
                            lineWidth: 1.5
                        )
                    Text(player.avatar)
                        .font(.system(size: 22))
                        .opacity(isSelected ? 1 : 0.3)

                    // Checkmark
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
                    .foregroundColor(isSelected ? Color(hex: "#1A1A1A") : Color(hex: "#CCCCCC"))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Group Card

    private let maxGroupSize = 4

    private func groupCardBorderColor(index: Int, playerCount: Int) -> Color {
        let isDragOver = dropTargetGroup == index
        if isDragOver && dragSourceGroup != index {
            let isFull = playerCount >= maxGroupSize
            return isFull
                ? Color(hex: "#E8A820").opacity(0.5)   // amber = swap
                : Color(hex: "#1A1A1A").opacity(0.5)    // dark = move
        }
        return Color(hex: "#EFEFEF")
    }

    private func groupCard(index: Int, players: [Player]) -> some View {
        let borderColor = groupCardBorderColor(index: index, playerCount: players.count)
        let borderWidth: CGFloat = dropTargetGroup == index ? 2 : 1

        return VStack(spacing: 0) {
            groupCardHeader(index: index)

            ForEach(players) { player in
                groupPlayerRow(player: player, groupIndex: index, isLast: player.id == players.last?.id)
            }

            Spacer().frame(height: 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .overlay(
            GeometryReader { geo in
                if dropTargetGroup == index,
                   let targetIdx = dropTargetIndex,
                   dragSourceGroup == index {
                    let headerHeight: CGFloat = 41
                    let rowHeight: CGFloat = 49
                    let y = headerHeight + CGFloat(targetIdx) * rowHeight
                    Capsule()
                        .fill(Color(hex: "#4A90D9"))
                        .frame(width: geo.size.width - 32, height: 2.5)
                        .position(x: geo.size.width / 2, y: y)
                }
            }
            .allowsHitTesting(false)
        )
        .onDrop(of: [.text], delegate: GroupDropDelegate(
            groupIndex: index,
            playerCount: players.count,
            maxGroupSize: maxGroupSize,
            dragSourceGroup: $dragSourceGroup,
            dropTargetGroup: $dropTargetGroup,
            dropTargetIndex: $dropTargetIndex,
            dragPlayer: $dragPlayer,
            groups: $groups,
            startingSides: $startingSides,
            teeTimes: $teeTimes,
            scorerIDs: $scorerIDs,
            showSwapPicker: $showSwapPicker,
            pendingSwapPlayer: $pendingSwapPlayer,
            pendingSwapFrom: $pendingSwapFrom,
            pendingSwapTo: $pendingSwapTo,
            syncTeeTimes: syncTeeTimes,
            syncScorerIDs: syncScorerIDs,
            syncSelectedTees: syncSelectedTees
        ))
    }

    private func groupCardHeader(index: Int) -> some View {
        HStack(spacing: 8) {
            // Left: group label / tee time
            if showTeeTimes, index < teeTimes.count, let time = teeTimes[index] {
                Text(Self.teeTimeFormatter.string(from: time))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
            } else {
                Text("Group \(index + 1)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
            }

            Spacer()

            // Edit / Add time button
            if showTeeTimes {
                Button {
                    teeTimePickerGroupIndex = index
                    teeTimePickerDate = teeTimes[index] ?? defaultFirstTeeTime()
                    showTeeTimePicker = true
                } label: {
                    if index < teeTimes.count, teeTimes[index] != nil {
                        Text("edit")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#BBBBBB"))
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Tee time")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "#BBBBBB"))
                    }
                }
            }

            // Move group icon
            if groups.count > 1 {
                Menu {
                    ForEach(0..<groups.count, id: \.self) { pos in
                        if pos != index {
                            Button {
                                moveGroup(from: index, to: pos)
                            } label: {
                                Label("Position \(pos + 1)", systemImage: pos < index ? "arrow.up" : "arrow.down")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#CCCCCC"))
                        .frame(width: 24, height: 24)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func groupPlayerRow(player: Player, groupIndex: Int, isLast: Bool) -> some View {
        let isDragging = dragPlayer?.id == player.id

        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: player.color).opacity(0.09))
                Circle()
                    .strokeBorder(Color(hex: player.color).opacity(0.25), lineWidth: 1.5)
                Text(player.avatar)
                    .font(.system(size: 16))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text("HCP \(String(format: "%.1f", player.handicap))")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#BBBBBB"))
            }

            Spacer()

            if groupIndex < scorerIDs.count && scorerIDs[groupIndex] == player.id {
                Button {
                    scorerPickerItem = SheetItem(id: groupIndex)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "pencil")
                            .font(.system(size: 8, weight: .semibold))
                        Text("Scorer")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#999999"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "#F0F0F0")))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }

            Menu {
                // Make Scorer option (only if not already scorer)
                if groupIndex < scorerIDs.count && scorerIDs[groupIndex] != player.id {
                    Button {
                        scorerIDs[groupIndex] = player.id
                    } label: {
                        Label("Make Scorer", systemImage: "pencil.line")
                    }

                    Divider()
                }

                ForEach(Array(groups.enumerated()), id: \.offset) { idx, _ in
                    if idx != groupIndex {
                        let isFull = groups[idx].count >= maxGroupSize
                        Button {
                            if isFull {
                                // Full group — trigger swap picker
                                pendingSwapPlayer = player
                                pendingSwapFrom = groupIndex
                                pendingSwapTo = idx
                                showSwapPicker = true
                            } else {
                                movePlayer(player, from: groupIndex, to: idx)
                            }
                        } label: {
                            Label(
                                isFull ? "Swap with Group \(idx + 1)" : "Move to Group \(idx + 1)",
                                systemImage: isFull ? "arrow.triangle.swap" : "arrow.right"
                            )
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#CCCCCC"))
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .opacity(1.0)
        .onDrag {
            dragPlayer = player
            dragSourceGroup = groupIndex
            return NSItemProvider(object: String(player.id) as NSString)
        }

        if !isLast {
            Rectangle()
                .fill(Color(hex: "#F5F5F5"))
                .frame(height: 1)
                .padding(.leading, 58)
        }
    }

    // MARK: - Drop Delegate (defined below)

    // MARK: - Tee Time Binding

    private func teeTimeBinding(for index: Int) -> Binding<Date>? {
        guard index < teeTimes.count, teeTimes[index] != nil else { return nil }
        return Binding<Date>(
            get: { teeTimes[index] ?? Date() },
            set: { teeTimes[index] = $0 }
        )
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        VStack(spacing: 0) {
            Text("Settings")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))
                .padding(.top, 24)
                .padding(.bottom, 20)

            // Tee times toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tee Times")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    Text("Assign a tee time per group")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#999999"))
                }
                Spacer()
                Toggle("", isOn: $showTeeTimes)
                    .labelsHidden()
                    .tint(Color(hex: "#1A1A1A"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Color(hex: "#F0F0F0"))
                .frame(height: 1)
                .padding(.horizontal, 20)

            // Carries toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Carries")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    Text("Squashed skins carry to the next hole")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#999999"))
                }
                Spacer()
                Toggle("", isOn: $carriesEnabled)
                    .labelsHidden()
                    .tint(Color(hex: "#1A1A1A"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // First tee time picker (when enabled)
            if showTeeTimes {
                Rectangle()
                    .fill(Color(hex: "#F0F0F0"))
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("First Tee Time")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                        Text("Groups auto-fill at 8-min intervals")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#999999"))
                    }
                    Spacer()
                    DatePicker(
                        "",
                        selection: Binding<Date>(
                            get: { teeTimes.first.flatMap { $0 } ?? defaultFirstTeeTime() },
                            set: { newTime in
                                if teeTimes.isEmpty { syncTeeTimes() }
                                teeTimes[0] = newTime
                                autoFillTeeTimes(from: 0)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            Spacer()
        }
    }

    // MARK: - Leaderboard Sheet

    private var leaderboardSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leaderboard")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(hex: "#1A1A1A"))
                    Text(groupName)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#999999"))
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "#C4A450"))
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)

            // Season stats header
            HStack {
                Text("ALL TIME")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(Color(hex: "#BBBBBB"))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Column headers
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 28) // rank column
                Text("Player")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#999999"))
                Spacer()
                Text("Skins")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#999999"))
                    .frame(width: 50, alignment: .center)
                Text("Net")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#999999"))
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color(hex: "#F0F0F0"))
                .frame(height: 1)
                .padding(.horizontal, 24)

            // Player rows — show all members sorted by skins (placeholder: all zeros for first-time group)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(allAvailable.enumerated()), id: \.element.id) { rank, player in
                        leaderboardRow(rank: rank + 1, player: player)

                        if rank < allAvailable.count - 1 {
                            Rectangle()
                                .fill(Color(hex: "#F5F5F5"))
                                .frame(height: 1)
                                .padding(.leading, 68)
                                .padding(.trailing, 24)
                        }
                    }
                }
            }

            Spacer()

            // Empty state message for first-time groups
            VStack(spacing: 8) {
                Text("No rounds played yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#999999"))
                Text("Stats will appear here after your first round.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#CCCCCC"))
            }
            .padding(.bottom, 32)
        }
    }

    private func leaderboardRow(rank: Int, player: Player) -> some View {
        HStack(spacing: 10) {
            // Rank
            Text("\(rank)")
                .font(.system(size: 13, weight: rank <= 3 ? .bold : .regular))
                .foregroundColor(rank <= 3 ? Color(hex: "#C4A450") : Color(hex: "#BBBBBB"))
                .frame(width: 22, alignment: .center)

            // Avatar
            ZStack {
                Circle()
                    .fill(Color(hex: player.color).opacity(0.09))
                Circle()
                    .strokeBorder(Color(hex: player.color).opacity(0.25), lineWidth: 1.5)
                Text(player.avatar)
                    .font(.system(size: 14))
            }
            .frame(width: 32, height: 32)

            // Name + HCP
            VStack(alignment: .leading, spacing: 1) {
                Text(player.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text("HCP \(String(format: "%.1f", player.handicap))")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#CCCCCC"))
            }

            Spacer()

            // Skins won (placeholder: 0)
            Text("0")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "#BBBBBB"))
                .frame(width: 50, alignment: .center)

            // Net winnings (placeholder: $0)
            Text("$0")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "#BBBBBB"))
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func defaultFirstTeeTime() -> Date {
        var cal = Calendar.current
        cal.timeZone = .current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 8
        comps.minute = 0
        return cal.date(from: comps) ?? Date()
    }

    // MARK: - Add Player Sheet

    private var addPlayerSheet: some View {
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
                        Text("Temporary player for this round")
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

            // Add to group option
            Button {
                showAddSheet = false
                // TODO: Invite existing Carry user flow
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
                        Text("Add to Group")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "#1A1A1A"))
                        Text("Invite an existing Carry member")
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

    // MARK: - Add Guest

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

        regroup()
    }

    // MARK: - Move Player

    private func movePlayer(_ player: Player, from sourceGroup: Int, to destGroup: Int) {
        withAnimation(.easeOut(duration: 0.2)) {
            guard sourceGroup < groups.count, destGroup < groups.count else { return }
            groups[sourceGroup].removeAll { $0.id == player.id }
            groups[destGroup].append(player)
            // Remove empty groups
            groups.removeAll { $0.isEmpty }
            // Adjust starting sides array
            while startingSides.count < groups.count {
                startingSides.append(startingSides.count % 2 == 0 ? "front" : "back")
            }
            while startingSides.count > groups.count {
                startingSides.removeLast()
            }
            syncTeeTimes()
            syncScorerIDs()
            syncSelectedTees()
        }
    }

    // MARK: - Move Group (reorder)

    private func moveGroup(from source: Int, to target: Int) {
        guard source != target, source < groups.count, target < groups.count else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            let group = groups.remove(at: source)
            groups.insert(group, at: target)

            let side = startingSides.remove(at: source)
            startingSides.insert(side, at: target)

            let teeTime = teeTimes.remove(at: source)
            teeTimes.insert(teeTime, at: target)

            let scorer = scorerIDs.remove(at: source)
            scorerIDs.insert(scorer, at: target)

            let tee = selectedTees.remove(at: source)
            selectedTees.insert(tee, at: target)
        }
    }
}

// MARK: - Group Drop Delegate

struct GroupDropDelegate: DropDelegate {
    let groupIndex: Int
    let playerCount: Int
    let maxGroupSize: Int
    @Binding var dragSourceGroup: Int?
    @Binding var dropTargetGroup: Int?
    @Binding var dropTargetIndex: Int?
    @Binding var dragPlayer: Player?
    @Binding var groups: [[Player]]
    @Binding var startingSides: [String]
    @Binding var teeTimes: [Date?]
    @Binding var scorerIDs: [Int]
    @Binding var showSwapPicker: Bool
    @Binding var pendingSwapPlayer: Player?
    @Binding var pendingSwapFrom: Int?
    @Binding var pendingSwapTo: Int?
    let syncTeeTimes: () -> Void
    let syncScorerIDs: () -> Void
    let syncSelectedTees: () -> Void

    // Layout constants for drop position calculation
    private let headerHeight: CGFloat = 41
    private let rowHeight: CGFloat = 49

    func dropEntered(info: DropInfo) {
        withAnimation(.easeOut(duration: 0.15)) {
            dropTargetGroup = groupIndex
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeOut(duration: 0.15)) {
            if dropTargetGroup == groupIndex {
                dropTargetGroup = nil
                dropTargetIndex = nil
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Calculate target row index for same-group reorder
        if dragSourceGroup == groupIndex {
            let y = info.location.y - headerHeight
            let idx = max(0, min(groups[groupIndex].count, Int(round(y / rowHeight))))
            withAnimation(.easeOut(duration: 0.1)) {
                dropTargetIndex = idx
            }
        } else {
            dropTargetIndex = nil
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let player = dragPlayer, let sourceGroup = dragSourceGroup else {
            resetDrag()
            return false
        }

        // Same group — reorder to drop position
        if sourceGroup == groupIndex {
            withAnimation(.easeOut(duration: 0.2)) {
                if let sourceIdx = groups[sourceGroup].firstIndex(where: { $0.id == player.id }) {
                    // Calculate target from drop position
                    let y = info.location.y - headerHeight
                    var targetIdx = max(0, min(groups[groupIndex].count, Int(round(y / rowHeight))))

                    let p = groups[sourceGroup].remove(at: sourceIdx)
                    // Adjust target since removal shifted indices
                    if targetIdx > sourceIdx { targetIdx -= 1 }
                    targetIdx = max(0, min(targetIdx, groups[sourceGroup].count))
                    groups[sourceGroup].insert(p, at: targetIdx)
                }
            }
            resetDrag()
            return true
        }

        // Full group — show swap picker, no move yet
        if playerCount >= maxGroupSize {
            pendingSwapPlayer = player
            pendingSwapFrom = sourceGroup
            pendingSwapTo = groupIndex
            showSwapPicker = true
            resetDrag()
            return true
        }

        // Not full — move directly
        withAnimation(.easeOut(duration: 0.2)) {
            groups[sourceGroup].removeAll { $0.id == player.id }
            groups[groupIndex].append(player)

            // Remove empty groups
            groups.removeAll { $0.isEmpty }

            // Sync arrays
            while startingSides.count < groups.count {
                startingSides.append(startingSides.count % 2 == 0 ? "front" : "back")
            }
            while startingSides.count > groups.count {
                startingSides.removeLast()
            }
            syncTeeTimes()
            syncScorerIDs()
            syncSelectedTees()
        }
        resetDrag()
        return true
    }

    private func resetDrag() {
        dragPlayer = nil
        dragSourceGroup = nil
        dropTargetGroup = nil
        dropTargetIndex = nil
    }
}
