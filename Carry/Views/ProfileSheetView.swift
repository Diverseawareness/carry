import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showSignOutConfirm = false
    @State private var showHandicapPicker = false
    @State private var showEditProfile = false
    @State private var showGhinEdit = false
    @State private var showNotifications = false
    @State private var pickerWhole: Int = 0
    @State private var pickerDecimal: Int = 0

    private var displayName: String { authService.currentUser?.displayName ?? "Player" }
    private var avatar: String { authService.currentUser?.avatar ?? "🏌️" }
    private var color: String { authService.currentUser?.color ?? "#D4A017" }
    private var handicap: Double { authService.currentUser?.handicap ?? 0 }
    private var ghinNumber: String? { authService.currentUser?.ghinNumber }

    var body: some View {
        ZStack {
            Color(hex: "#F0F0F0").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // MARK: Header
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: color).opacity(0.12))
                            Circle()
                                .strokeBorder(Color(hex: color).opacity(0.3), lineWidth: 2)
                            Text(avatar)
                                .font(.system(size: 44))
                        }
                        .frame(width: 88, height: 88)
                        .padding(.top, 24)

                        Text(displayName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Color(hex: "#1A1A1A"))

                        HStack(spacing: 8) {
                            Label {
                                Text("HCP \(String(format: "%.1f", handicap))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color(hex: "#C4A450"))
                            } icon: {
                                Image(systemName: "figure.golf")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "#C4A450"))
                            }

                            if let ghin = ghinNumber, !ghin.isEmpty {
                                Text("·")
                                    .foregroundColor(Color(hex: "#CCCCCC"))
                                Text("GHIN \(ghin)")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "#999999"))
                            }
                        }
                        .padding(.bottom, 24)
                    }

                    // MARK: Account Section
                    sectionHeader("ACCOUNT")

                    settingsGroup {
                        settingsRow(
                            iconName: "person.fill",
                            iconColor: "#4A90D9",
                            label: "Edit Profile"
                        ) {
                            showEditProfile = true
                        }

                        divider()

                        settingsRow(
                            iconName: "gauge",
                            iconColor: "#2ECC71",
                            label: "Handicap Index",
                            value: String(format: "%.1f", handicap),
                            chevronIcon: "chevron.up.chevron.down"
                        ) {
                            pickerWhole = Int(handicap)
                            pickerDecimal = Int((handicap - Double(Int(handicap))) * 10)
                            showHandicapPicker = true
                        }

                        divider()

                        settingsRow(
                            iconName: "number",
                            iconColor: "#E67E22",
                            label: "GHIN Number",
                            value: ghinNumber ?? "Not set"
                        ) {
                            showGhinEdit = true
                        }
                    }

                    // MARK: Preferences Section
                    sectionHeader("PREFERENCES")

                    settingsGroup {
                        settingsRow(
                            iconName: "bell.fill",
                            iconColor: "#9B59B6",
                            label: "Notifications"
                        ) {
                            showNotifications = true
                        }
                    }

                    // MARK: About Section
                    sectionHeader("ABOUT")

                    settingsGroup {
                        settingsRow(
                            iconName: "doc.text.fill",
                            iconColor: "#34495E",
                            label: "Terms of Service"
                        ) {
                            if let url = URL(string: "https://carry.golf/terms") {
                                UIApplication.shared.open(url)
                            }
                        }

                        divider()

                        settingsRow(
                            iconName: "hand.raised.fill",
                            iconColor: "#34495E",
                            label: "Privacy Policy"
                        ) {
                            if let url = URL(string: "https://carry.golf/privacy") {
                                UIApplication.shared.open(url)
                            }
                        }

                        divider()

                        settingsRow(
                            iconName: "info.circle.fill",
                            iconColor: "#BBBBBB",
                            label: "Version",
                            value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                            showChevron: false
                        ) {}
                    }

                    // MARK: Sign Out
                    settingsGroup {
                        Button {
                            showSignOutConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Sign Out")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Color(hex: "#E05555"))
                                Spacer()
                            }
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)

                    Spacer().frame(height: 40)
                }
            }
        }
        .confirmationDialog("Sign out of Carry?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { try? await authService.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showHandicapPicker) {
            handicapPickerSheet
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet()
                .environmentObject(authService)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGhinEdit) {
            GhinEditSheet()
                .environmentObject(authService)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Handicap Picker

    private var handicapPickerSheet: some View {
        VStack(spacing: 0) {
            // Header with done button
            HStack {
                Button("Cancel") {
                    showHandicapPicker = false
                }
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "#999999"))

                Spacer()

                Text("Handicap Index")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))

                Spacer()

                Button("Save") {
                    let newHandicap = Double(pickerWhole) + Double(pickerDecimal) / 10.0
                    Task {
                        try? await authService.updateProfile(ProfileUpdate(handicap: newHandicap))
                    }
                    showHandicapPicker = false
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "#C4A450"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            // Wheel picker
            HStack(spacing: 0) {
                Picker("Whole", selection: $pickerWhole) {
                    ForEach(-5...54, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.wheel)

                Text(".")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Color(hex: "#1A1A1A"))

                Picker("Decimal", selection: $pickerDecimal) {
                    ForEach(0...9, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 80)
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(Color(hex: "#999999"))
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white)
        )
        .padding(.horizontal, 20)
    }

    private func divider() -> some View {
        Rectangle()
            .fill(Color(hex: "#F0F0F0"))
            .frame(height: 1)
            .padding(.leading, 58)
    }

    private func settingsRow(
        iconName: String,
        iconColor: String,
        label: String,
        value: String? = nil,
        showChevron: Bool = true,
        chevronIcon: String = "chevron.right",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: iconColor))
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(width: 32, height: 32)

                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "#1A1A1A"))

                Spacer()

                if let value {
                    Text(value)
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: "#AAAAAA"))
                }

                if showChevron {
                    Image(systemName: chevronIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#CCCCCC"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    @State private var name: String = ""
    @State private var selectedColor: String = "#D4A017"
    @State private var selectedAvatar: String = "🏌️"
    @State private var isSaving = false

    private let colorOptions = [
        "#D4A017", "#4A90D9", "#E05555", "#2ECC71",
        "#9B59B6", "#E67E22", "#1ABC9C", "#34495E",
        "#C0392B", "#2980B9", "#27AE60", "#F39C12",
    ]

    private let avatarOptions = [
        "🏌️", "🧢", "🦅", "🍺", "🎩", "🕶️",
        "🐊", "⛳", "🔥", "🎯", "🌴", "☀️",
        "🏆", "💰", "🦈", "🐻", "🎱", "🍀",
        "🌊", "⚡", "🎪", "🦁", "🐉", "🪶",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "#999999"))

                Spacer()

                Text("Edit Profile")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))

                Spacer()

                Button("Save") { saveProfile() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSaving ? Color(hex: "#CCCCCC") : Color(hex: "#C4A450"))
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 24) {
                    // Live preview
                    ZStack {
                        Circle()
                            .fill(Color(hex: selectedColor).opacity(0.12))
                        Circle()
                            .strokeBorder(Color(hex: selectedColor).opacity(0.3), lineWidth: 2)
                        Text(selectedAvatar)
                            .font(.system(size: 44))
                    }
                    .frame(width: 88, height: 88)
                    .padding(.top, 8)

                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NAME")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(Color(hex: "#BBBBBB"))
                            .padding(.leading, 4)

                        TextField("Your name", text: $name)
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

                    // Color picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("COLOR")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(Color(hex: "#BBBBBB"))
                            .padding(.leading, 4)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                            ForEach(colorOptions, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.white, lineWidth: selectedColor == hex ? 3 : 0)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color(hex: hex).opacity(0.5), lineWidth: selectedColor == hex ? 1 : 0)
                                            .padding(-1)
                                    )
                                    .scaleEffect(selectedColor == hex ? 1.1 : 1.0)
                                    .animation(.easeOut(duration: 0.15), value: selectedColor)
                                    .onTapGesture { selectedColor = hex }
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Avatar picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("AVATAR")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(Color(hex: "#BBBBBB"))
                            .padding(.leading, 4)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                            ForEach(avatarOptions, id: \.self) { emoji in
                                Text(emoji)
                                    .font(.system(size: 28))
                                    .frame(width: 48, height: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedAvatar == emoji ? Color(hex: selectedColor).opacity(0.1) : .white)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(
                                                selectedAvatar == emoji ? Color(hex: selectedColor).opacity(0.4) : Color(hex: "#EFEFEF"),
                                                lineWidth: selectedAvatar == emoji ? 2 : 1
                                            )
                                    )
                                    .onTapGesture { selectedAvatar = emoji }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color(hex: "#F0F0F0"))
        .onAppear {
            name = authService.currentUser?.displayName ?? ""
            selectedColor = authService.currentUser?.color ?? "#D4A017"
            selectedAvatar = authService.currentUser?.avatar ?? "🏌️"
        }
    }

    private func saveProfile() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true

        Task {
            try? await authService.updateProfile(ProfileUpdate(
                displayName: trimmed,
                initials: String(trimmed.prefix(2)).uppercased(),
                color: selectedColor,
                avatar: selectedAvatar
            ))
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - GHIN Edit Sheet

struct GhinEditSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    @State private var ghinNumber: String = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "#999999"))

                Spacer()

                Text("GHIN Number")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))

                Spacer()

                Button("Save") { saveGhin() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSaving ? Color(hex: "#CCCCCC") : Color(hex: "#C4A450"))
                    .disabled(isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 6) {
                Text("GHIN NUMBER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(Color(hex: "#BBBBBB"))
                    .padding(.leading, 4)

                TextField("e.g. 1234567", text: $ghinNumber)
                    .font(.system(size: 16))
                    .keyboardType(.numberPad)
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

                Text("Your Golf Handicap Information Network number. Find it on your GHIN card or the GHIN app.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#BBBBBB"))
                    .padding(.top, 4)
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(Color(hex: "#F0F0F0"))
        .onAppear {
            ghinNumber = authService.currentUser?.ghinNumber ?? ""
        }
    }

    private func saveGhin() {
        isSaving = true
        let value = ghinNumber.trimmingCharacters(in: .whitespaces)
        Task {
            try? await authService.updateProfile(ProfileUpdate(
                ghinNumber: value.isEmpty ? nil : value
            ))
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Notifications Sheet

struct NotificationsSheet: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("notif_roundInvites") private var roundInvites = true
    @AppStorage("notif_scoreUpdates") private var scoreUpdates = true
    @AppStorage("notif_skinsWon") private var skinsWon = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Text("Notifications")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button("Done") { dismiss() }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: "#C4A450"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)

            VStack(spacing: 0) {
                notifToggle(
                    icon: "envelope.fill",
                    iconColor: "#4A90D9",
                    label: "Round Invites",
                    subtitle: "When someone invites you to a skins game",
                    isOn: $roundInvites
                )

                Rectangle()
                    .fill(Color(hex: "#F0F0F0"))
                    .frame(height: 1)
                    .padding(.leading, 58)

                notifToggle(
                    icon: "pencil.line",
                    iconColor: "#2ECC71",
                    label: "Score Updates",
                    subtitle: "When scores are entered in your round",
                    isOn: $scoreUpdates
                )

                Rectangle()
                    .fill(Color(hex: "#F0F0F0"))
                    .frame(height: 1)
                    .padding(.leading, 58)

                notifToggle(
                    icon: "dollarsign.circle.fill",
                    iconColor: "#C4A450",
                    label: "Skins Won",
                    subtitle: "When someone wins a skin in your game",
                    isOn: $skinsWon
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white)
            )
            .padding(.horizontal, 20)

            Text("Push notifications require permission in iOS Settings.")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#BBBBBB"))
                .padding(.top, 12)
                .padding(.horizontal, 24)

            Spacer()
        }
        .background(Color(hex: "#F0F0F0"))
    }

    private func notifToggle(icon: String, iconColor: String, label: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: iconColor))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "#1A1A1A"))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#AAAAAA"))
            }

            Spacer()

            Toggle("", isOn: isOn)
                .tint(Color(hex: "#C4A450"))
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
