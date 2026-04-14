import SwiftUI
import PhotosUI
import StoreKit

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var storeService: StoreService
    @Binding var skinGameGroups: [SavedGroup]
    @State private var showSignOutConfirm = false
    @State private var showHandicapPicker = false
    @State private var showEditProfile = false
    @State private var showGhinEdit = false
    @State private var showNotifications = false
    @State private var showClubEdit = false
    @State private var showPaywall = false
    @State private var showPhotoPicker = false
    @State private var showPhotoOptions = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var profileImage: UIImage? = nil
    @State private var hcPickerValue: Double = 0
    @State private var hcPickerIsPlus: Bool = false
    @State private var profileError: String?
    @State private var showProfileError = false
    @State private var imageToCrop: UIImage? = nil
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false

    private var fullName: String {
        let first = authService.currentUser?.firstName ?? ""
        let last = authService.currentUser?.lastName ?? ""
        let combined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return combined.isEmpty ? (authService.currentUser?.displayName ?? "Player") : combined
    }
    private var initials: String { authService.currentUser?.initials ?? "P" }
    private var handicap: Double { authService.currentUser?.handicap ?? 0 }
    private var ghinNumber: String? { authService.currentUser?.ghinNumber }

    private var homeClub: String? { authService.currentUser?.homeClub }
    private var avatarUrl: String? { authService.currentUser?.avatarUrl }
    private var hasPhoto: Bool { profileImage != nil || avatarUrl != nil }
    private var profileSubtitle: String {
        var parts: [String] = []
        if let homeClub, !homeClub.isEmpty { parts.append(homeClub) }
        parts.append("HCP \(formatHandicap(handicap))")
        return parts.joined(separator: " · ")
    }
    private var totalGamesPlayed: Int {
        skinGameGroups.reduce(0) { $0 + $1.roundHistory.count }
    }
    private var totalSkinsWon: Int {
        skinGameGroups.reduce(0) { groupTotal, group in
            let concluded = (group.concludedRound.map { [$0] } ?? [])
            let history = group.roundHistory
            return groupTotal + (concluded + history).reduce(0) { $0 + $1.yourSkins }
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Profile Header (sticky)
            HStack(spacing: 20) {
                // Avatar — tappable
                Button {
                    showPhotoOptions = true
                } label: {
                    if let profileImage {
                        Image(uiImage: profileImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 86, height: 86)
                            .clipShape(Circle())
                    } else if let avatarUrl, let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 86, height: 86)
                                    .clipShape(Circle())
                            default:
                                ZStack {
                                    Circle()
                                        .fill(Color.mintLight)
                                    Circle()
                                        .strokeBorder(Color.mintBright, lineWidth: 1.5)
                                    Text(initials)
                                        .font(.custom("ANDONESI-Regular", size: 35))
                                        .foregroundColor(Color.greenDark)
                                }
                                .frame(width: 86, height: 86)
                            }
                        }
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.mintLight)
                            Circle()
                                .strokeBorder(Color.mintBright, lineWidth: 1.5)
                            Text(initials)
                                .font(.custom("ANDONESI-Regular", size: 35))
                                .foregroundColor(Color.greenDark)
                        }
                        .frame(width: 86, height: 86)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile photo")
                .accessibilityHint("Double tap to change your profile photo")

                // Name + subtitle + stats
                VStack(alignment: .leading, spacing: 2) {
                    Text(fullName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(hexString: "171D28"))
                        .lineLimit(1)

                    Text(profileSubtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hexString: "7A7A7E"))
                        .lineLimit(1)

                    Text("\(totalGamesPlayed) Games · \(totalSkinsWon) Skins")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hexString: "171D28"))
                        .padding(.top, 2)
                        .accessibilityLabel("\(totalGamesPlayed) games played, \(totalSkinsWon) skins won")
                }

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .background(.white)

            ScrollView {
                VStack(spacing: 0) {
                    // MARK: Subscription / Upgrade
                    if storeService.isPremium {
                        capsHeader("SUBSCRIPTION")
                        settingsGroup {
                            plainRow("Manage Subscription") {
                                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            groupDivider()
                            plainRow("Restore Purchases") {
                                Task { try? await AppStore.sync() }
                            }
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 10) {
                                Image("premium-crown")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                Text("Upgrade to Premium")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.deepNavy)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.deepNavy, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }

                    // MARK: Account
                    capsHeader("ACCOUNT")
                    settingsGroup {
                        plainRow("Profile") {
                            showEditProfile = true
                        }
                        groupDivider()
                        plainRow("GHIN Nr", value: ghinNumber) {
                            showGhinEdit = true
                        }
                        groupDivider()
                        plainRow("Notifications") {
                            showNotifications = true
                        }
                    }

                    // MARK: About
                    capsHeader("ABOUT")
                    settingsGroup {
                        plainRow("App FAQ") {
                            if let url = URL(string: "https://carryapp.site/faq.html") {
                                UIApplication.shared.open(url)
                            }
                        }
                        groupDivider()
                        plainRow("Terms of Service") {
                            if let url = URL(string: "https://carryapp.site/terms.html") {
                                UIApplication.shared.open(url)
                            }
                        }
                        groupDivider()
                        plainRow("Privacy Policy") {
                            if let url = URL(string: "https://carryapp.site/privacy.html") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }

                    // MARK: Support
                    capsHeader("SUPPORT")
                    settingsGroup {
                        plainRow("Contact Support") {
                            if let url = URL(string: "mailto:support@carryapp.site") {
                                UIApplication.shared.open(url)
                            }
                        }
                        groupDivider()
                        plainRow("Share Carry with a Friend") {
                            showShareSheet = true
                        }
                    }

                    // MARK: Data
                    capsHeader("DATA")
                    settingsGroup {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Text("Delete Account")
                                .font(.system(size: 16))
                                .foregroundColor(Color.systemRedColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("This permanently removes your account and all data from our servers.")
                        .font(.system(size: 13))
                        .foregroundColor(Color.textSecondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 6)

                    // MARK: Sign Out
                    settingsGroup {
                        plainRow("Sign Out") {
                            showSignOutConfirm = true
                        }
                    }
                    .padding(.top, 16)

                    // MARK: Version
                    settingsGroup {
                        HStack {
                            Text("Version")
                                .font(.system(size: 16))
                                .foregroundColor(Color.textPrimary)
                            Spacer()
                            Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                                .font(.system(size: 16))
                                .foregroundColor(Color.textSecondary)
                        }
                        .padding(.vertical, 14)
                    }
                    .padding(.top, 8)

                    // MARK: Disclaimer
                    Text("Carry is a scorekeeper only. Dollar amounts are for tracking friendly skins games. No real money is processed, held, or transferred through this app. Players settle up independently and are responsible for complying with local laws.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.textDisabled)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    Spacer().frame(height: 40)
                }
            }

        }
        .background(Color.white.ignoresSafeArea())
        .confirmationDialog("Sign out of Carry?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task {
                    do {
                        try await authService.signOut()
                    } catch {
                        profileError = "Could not sign out. Please try again."
                        showProfileError = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                Task {
                    do {
                        try await authService.deleteAccount()
                        await MainActor.run {
                            ToastManager.shared.success("Account deleted")
                        }
                    } catch {
                        await MainActor.run {
                            profileError = "Could not delete account. Please try again or contact support@carryapp.site."
                            showProfileError = true
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your account and all data. This cannot be undone.")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(items: [URL(string: "https://carryapp.site")!])
        }
        .sheet(isPresented: $showHandicapPicker) {
            HandicapPickerSheet(
                handicap: $hcPickerValue,
                isPlus: $hcPickerIsPlus
            )
            .presentationDetents([.height(520)])
            .presentationDragIndicator(.visible)
            .onDisappear {
                let newHandicap = hcPickerValue
                Task {
                    do {
                        try await authService.updateProfile(ProfileUpdate(handicap: newHandicap))
                        ToastManager.shared.success("Handicap updated")
                    } catch {
                        profileError = "Could not update handicap. Please try again."
                        showProfileError = true
                    }
                }
            }
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet(parentProfileImage: $profileImage)
                .environmentObject(authService)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showClubEdit) {
            ClubEditSheet()
                .environmentObject(authService)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showGhinEdit) {
            GhinEditSheet()
                .environmentObject(authService)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .confirmationDialog("Profile Photo", isPresented: $showPhotoOptions, titleVisibility: .visible) {
            Button("Take Photo") { showCamera = true }
            Button("Choose from Library") { showPhotoPicker = true }
            if hasPhoto {
                Button("Remove Photo", role: .destructive) { removePhoto() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(
                onCapture: { image in
                    showCamera = false
                    withAnimation(.easeOut(duration: 0.2)) {
                        imageToCrop = image
                    }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) {
            Task {
                do {
                    if let data = try await photoItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            imageToCrop = uiImage
                        }
                    }
                } catch {
                    profileError = "Could not load photo."
                    showProfileError = true
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { imageToCrop != nil },
            set: { if !$0 { imageToCrop = nil } }
        )) {
            if let cropImage = imageToCrop {
                ImageCropView(
                    image: cropImage,
                    onSave: { cropped in
                        profileImage = cropped
                        uploadPhoto(cropped)
                        imageToCrop = nil
                        photoItem = nil
                    },
                    onCancel: {
                        photoItem = nil
                        imageToCrop = nil
                    }
                )
                .ignoresSafeArea()
            }
        }
        .alert("Update Failed", isPresented: $showProfileError) {
            Button("OK") { }
        } message: {
            Text(profileError ?? "Something went wrong.")
        }
    }

    // MARK: - Photo Helpers

    private func uploadPhoto(_ image: UIImage) {
        Task {
            do {
                let url = try await authService.uploadAvatar(image)
                if !url.isEmpty {
                    try await authService.updateProfile(ProfileUpdate(avatarUrl: url))
                }
                await MainActor.run {
                    ToastManager.shared.success("Photo updated")
                }
            } catch {
                #if DEBUG
                print("[Photo] Upload failed: \(error)")
                #endif
                await MainActor.run {
                    profileError = "Upload error: \(error.localizedDescription)"
                    showProfileError = true
                }
            }
        }
    }

    private func removePhoto() {
        profileImage = nil
        photoItem = nil
        Task {
            do {
                try await authService.updateProfile(ProfileUpdate(avatarUrl: ""))
                ToastManager.shared.success("Photo removed")
            } catch {
                profileError = "Could not remove photo."
                showProfileError = true
            }
        }
    }

    // MARK: - Handicap Picker

    // Old handicapPickerSheet removed — uses shared HandicapPickerSheet component

    // MARK: - Components

    // MARK: - Settings Helpers

    private func capsHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.textSecondary)
                .tracking(1)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 8)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.bgSecondary)
        )
        .padding(.horizontal, 20)
    }

    private func groupDivider() -> some View {
        Rectangle()
            .fill(Color(hexString: "#DADADA"))
            .frame(height: 1)
    }

    private func plainRow(_ label: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(Color.textPrimary)

                Spacer()

                if let value, !value.isEmpty {
                    Text(value)
                        .font(.system(size: 15))
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 160, alignment: .trailing)
                }
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    @Binding var parentProfileImage: UIImage?
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var handicap: String = ""
    @State private var showHCPicker = false
    @State private var hcPickerValue: Double = 0
    @State private var hcPickerIsPlus: Bool = false
    enum ProfileField: Hashable { case firstName, lastName, handicap, clubSearch }
    @FocusState private var profileFocused: ProfileField?
    @State private var selectedPhoto: UIImage? = nil
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var showPhotoOptions = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoRemoved = false
    @State private var imageToCrop: UIImage? = nil
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    // Club search state
    @State private var selectedClub: GolfCourseResult? = nil
    @State private var clubSearchText = ""
    @State private var clubSearchResults: [GolfCourseResult] = []
    @State private var isSearchingClub = false
    @State private var clubSearchTask: Task<Void, Never>?
    @State private var hasExistingClub = false
    @State private var isClubMember = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZStack {
                Text("Edit Profile")
                    .font(.carry.headline)
                    .foregroundColor(Color.pureBlack)

                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16))
                        .foregroundColor(Color.textTertiary)

                    Spacer()

                    Button("Save") { saveProfile() }
                        .font(.carry.bodyLGSemibold)
                        .foregroundColor(isSaving ? Color.textDisabled : Color.textPrimary)
                        .disabled(isSaving || firstName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    // Photo picker
                    HStack {
                        Spacer()
                        Button { showPhotoOptions = true } label: {
                            ZStack {
                                if let image = selectedPhoto {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                } else if !photoRemoved,
                                          let urlStr = authService.currentUser?.avatarUrl,
                                          let url = URL(string: urlStr) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(Circle())
                                        default:
                                            ZStack {
                                                Circle()
                                                    .fill(Color.mintLight)
                                                Circle()
                                                    .strokeBorder(Color.mintBright, lineWidth: 1.5)
                                                Text(authService.currentUser?.initials ?? "P")
                                                    .font(.custom("ANDONESI-Regular", size: 38))
                                                    .foregroundColor(Color.greenDark)
                                            }
                                            .frame(width: 100, height: 100)
                                        }
                                    }
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(Color.mintLight)
                                        Circle()
                                            .strokeBorder(Color.mintBright, lineWidth: 1.5)
                                        Text(authService.currentUser?.initials ?? "P")
                                            .font(.custom("ANDONESI-Regular", size: 38))
                                            .foregroundColor(Color.greenDark)
                                    }
                                    .frame(width: 100, height: 100)
                                }

                                // Edit badge
                                Circle()
                                    .fill(Color.textPrimary)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Image(systemName: selectedPhoto != nil || (!photoRemoved && authService.currentUser?.avatarUrl != nil) ? "pencil" : "camera.fill")
                                            .font(.carry.captionBold)
                                            .foregroundColor(.white)
                                    )
                                    .offset(x: 36, y: 36)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit profile photo")
                        .accessibilityHint("Opens photo picker")
                        Spacer()
                    }
                    .padding(.top, 8)

                    if selectedPhoto != nil || (!photoRemoved && authService.currentUser?.avatarUrl != nil) {
                        Button {
                            selectedPhoto = nil
                            photoItem = nil
                            photoRemoved = true
                        } label: {
                            Text("Remove photo")
                                .font(.system(size: 14))
                                .foregroundColor(Color.textDisabled)
                        }
                    }

                    // First Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("First Name")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                            .padding(.leading, 4)

                        TextField("First name", text: $firstName)
                            .font(.system(size: 16))
                            .textContentType(.givenName)
                            .focused($profileFocused, equals: .firstName)
                            .carryInput(focused: profileFocused == .firstName)
                    }
                    .padding(.horizontal, 24)

                    // Last Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last Name")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                            .padding(.leading, 4)

                        TextField("Last name", text: $lastName)
                            .font(.system(size: 16))
                            .textContentType(.familyName)
                            .focused($profileFocused, equals: .lastName)
                            .carryInput(focused: profileFocused == .lastName)
                    }
                    .padding(.horizontal, 24)

                    // Handicap field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Handicap")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                            .padding(.leading, 4)

                        Button {
                            profileFocused = nil
                            let val: Double = handicap.hasPrefix("+") ? -(Double(String(handicap.dropFirst())) ?? 0) : Double(handicap) ?? 0
                            hcPickerValue = val
                            hcPickerIsPlus = val < 0
                            showHCPicker = true
                        } label: {
                            HStack {
                                Text(handicap.isEmpty ? "e.g. 12.4" : handicap)
                                    .font(.system(size: 16))
                                    .foregroundColor(handicap.isEmpty ? Color.textDisabled : Color.textPrimary)
                                Spacer()
                            }
                            .carryInput(focused: false)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)

                    // Home Club / Home Course
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Home Course")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                            .padding(.leading, 4)

                        if let club = selectedClub {
                            // Selected club with "Change" button
                            Button {
                                selectedClub = nil
                                clubSearchText = ""
                                hasExistingClub = false
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(club.clubName ?? club.courseName ?? "Golf Club")
                                            .font(.carry.bodySemibold)
                                            .foregroundColor(Color.textPrimary)
                                        if !club.locationLabel.isEmpty {
                                            Text(club.locationLabel)
                                                .font(.system(size: 13))
                                                .foregroundColor(Color.textTertiary)
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
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.borderLight, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        } else if hasExistingClub, let clubName = authService.currentUser?.homeClub, !clubName.isEmpty {
                            // Existing club name from profile (no GolfCourseResult)
                            Button {
                                hasExistingClub = false
                                clubSearchText = ""
                            } label: {
                                HStack(spacing: 10) {
                                    Text(clubName)
                                        .font(.carry.bodySemibold)
                                        .foregroundColor(Color.textPrimary)

                                    Spacer()

                                    Text("Change")
                                        .font(.carry.captionLG)
                                        .foregroundColor(Color.textTertiary)
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.borderLight, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Search field
                            HStack(spacing: 8) {
                                if isSearchingClub {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color.textDisabled)
                                }

                                TextField("Search golf clubs", text: $clubSearchText)
                                    .font(.system(size: 16))
                                    .focused($profileFocused, equals: .clubSearch)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .onChange(of: clubSearchText) {
                                        debounceClubSearch(clubSearchText)
                                    }

                                if !clubSearchText.isEmpty {
                                    Button {
                                        clubSearchText = ""
                                        clubSearchResults = []
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Color.textDisabled)
                                    }
                                    .accessibilityLabel("Clear search")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(profileFocused == .clubSearch ? Color(hexString: "#333333") : Color.borderLight, lineWidth: profileFocused == .clubSearch ? 1.5 : 1)
                            )
                            .animation(.easeOut(duration: 0.15), value: profileFocused)

                            // Search results
                            if !clubSearchResults.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(clubSearchResults.prefix(5)) { course in
                                        Button {
                                            selectedClub = course
                                            clubSearchText = ""
                                            clubSearchResults = []
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(course.clubName ?? course.courseName ?? "Golf Club")
                                                    .font(.carry.body)
                                                    .foregroundColor(Color.textPrimary)
                                                if !course.locationLabel.isEmpty {
                                                    Text(course.locationLabel)
                                                        .font(.system(size: 13))
                                                        .foregroundColor(Color.textTertiary)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                        }
                                        .buttonStyle(.plain)

                                        if course.id != clubSearchResults.prefix(5).last?.id {
                                            Rectangle()
                                                .fill(Color.bgPrimary)
                                                .frame(height: 1)
                                                .padding(.leading, 16)
                                        }
                                    }
                                }
                                .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.borderLight, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .id("homeCourse")

                    // Membership — shown when a club is selected or exists
                    if selectedClub != nil || hasExistingClub {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Membership")
                                .font(.carry.bodySMBold)
                                .foregroundColor(Color.textPrimary)
                                .padding(.leading, 4)

                            MembershipRadioButton(
                                label: "Club Member",
                                subtitle: "I'm a member at this course",
                                isSelected: isClubMember
                            ) {
                                withAnimation(.easeOut(duration: 0.15)) { isClubMember = true }
                            }

                            MembershipRadioButton(
                                label: "Home Course Only",
                                subtitle: "I play here regularly but I'm not a member",
                                isSelected: !isClubMember
                            ) {
                                withAnimation(.easeOut(duration: 0.15)) { isClubMember = false }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 40)
            }
            .onChange(of: profileFocused) {
                if profileFocused == .clubSearch {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation { proxy.scrollTo("homeCourse", anchor: .center) }
                    }
                }
            }
            } // ScrollViewReader
        }
        .background(Color.white)
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
                    handicap = "+\(String(format: "%.1f", absVal))"
                } else {
                    handicap = String(format: "%.1f", absVal)
                }
            }
        }
        .onAppear {
            firstName = authService.currentUser?.firstName ?? ""
            lastName = authService.currentUser?.lastName ?? ""
            selectedPhoto = parentProfileImage
            if let club = authService.currentUser?.homeClub, !club.isEmpty {
                hasExistingClub = true
            }
            isClubMember = authService.currentUser?.isClubMember ?? true
            if let hcp = authService.currentUser?.handicap {
                handicap = String(format: hcp.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", hcp)
            }
        }
        .confirmationDialog("Profile Photo", isPresented: $showPhotoOptions, titleVisibility: .visible) {
            Button("Take Photo") { showCamera = true }
            Button("Choose from Library") { showPhotoPicker = true }
            if selectedPhoto != nil || (!photoRemoved && authService.currentUser?.avatarUrl != nil) {
                Button("Remove Photo", role: .destructive) {
                    selectedPhoto = nil
                    photoItem = nil
                    photoRemoved = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(
                onCapture: { image in
                    showCamera = false
                    withAnimation(.easeOut(duration: 0.2)) {
                        imageToCrop = image
                    }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) {
            Task {
                if let data = try? await photoItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        imageToCrop = uiImage
                    }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { imageToCrop != nil },
            set: { if !$0 { imageToCrop = nil } }
        )) {
            if let cropImage = imageToCrop {
                ImageCropView(
                    image: cropImage,
                    onSave: { cropped in
                        selectedPhoto = cropped
                        photoRemoved = false
                        imageToCrop = nil
                        photoItem = nil
                    },
                    onCancel: {
                        photoItem = nil
                        imageToCrop = nil
                    }
                )
                .ignoresSafeArea()
            }
        }
        .alert("Update Failed", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
    }

    private func saveProfile() {
        let firstTrimmed = firstName.trimmingCharacters(in: .whitespaces)
        let lastTrimmed = lastName.trimmingCharacters(in: .whitespaces)
        guard !firstTrimmed.isEmpty else { return }
        isSaving = true

        Task {
            do {
                // Upload new photo if selected
                var avatarUrl: String? = nil
                if let photo = selectedPhoto {
                    avatarUrl = try await authService.uploadAvatar(photo)
                } else if photoRemoved {
                    avatarUrl = ""  // Clear the avatar URL
                }

                let parsedHandicap = Double(handicap.trimmingCharacters(in: .whitespaces))
                let displayName = firstTrimmed  // First name only for scorecard/pills
                let initials: String = {
                    let first = firstTrimmed.prefix(1).uppercased()
                    let last = lastTrimmed.prefix(1).uppercased()
                    return last.isEmpty ? String(firstTrimmed.prefix(2)).uppercased() : "\(first)\(last)"
                }()

                // Determine club name and ID
                var clubName: String?
                var clubId: Int?
                if let club = selectedClub {
                    clubName = club.clubName ?? club.courseName
                    clubId = club.id
                } else if hasExistingClub {
                    clubName = authService.currentUser?.homeClub
                    clubId = authService.currentUser?.homeClubId
                }

                var update = ProfileUpdate(
                    firstName: firstTrimmed,
                    lastName: lastTrimmed,
                    displayName: displayName,
                    initials: initials,
                    handicap: parsedHandicap ?? 0,
                    homeClub: clubName,
                    homeClubId: clubId,
                    isClubMember: (selectedClub != nil || hasExistingClub) ? isClubMember : nil
                )
                if let avatarUrl {
                    update.avatarUrl = avatarUrl
                }

                try await authService.updateProfile(update)
                // Sync photo back to parent ProfileView
                if let photo = selectedPhoto {
                    parentProfileImage = photo
                } else if photoRemoved {
                    parentProfileImage = nil
                }
                isSaving = false
                ToastManager.shared.success("Profile updated")
                dismiss()
            } catch {
                isSaving = false
                ToastManager.shared.error("Could not update profile. Please try again.")
                showError = true
            }
        }
    }

    private func debounceClubSearch(_ query: String) {
        clubSearchTask?.cancel()

        guard query.count >= 2 else {
            clubSearchResults = []
            isSearchingClub = false
            return
        }

        isSearchingClub = true

        clubSearchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }

            do {
                let results = try await GolfCourseService.shared.searchCourses(query: query)
                guard !Task.isCancelled else { return }
                clubSearchResults = results
            } catch {
                guard !Task.isCancelled else { return }
                clubSearchResults = []
            }
            isSearchingClub = false
        }
    }

}

// MARK: - GHIN Edit Sheet

struct GhinEditSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    @State private var ghinNumber: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundColor(Color.textTertiary)

                Spacer()

                Text("GHIN Number")
                    .font(.carry.headline)
                    .foregroundColor(Color.pureBlack)

                Spacer()

                Button("Save") { saveGhin() }
                    .font(.carry.bodyLGSemibold)
                    .foregroundColor(isSaving ? Color.textDisabled : Color.textPrimary)
                    .disabled(isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 6) {
                Text("GHIN Number")
                    .font(.carry.bodySMBold)
                    .foregroundColor(Color.textPrimary)
                    .padding(.leading, 4)

                TextField("6-8 numbers", text: $ghinNumber)
                    .font(.system(size: 16))
                    .keyboardType(.numberPad)
                    .onChange(of: ghinNumber) {
                        let filtered = ghinNumber.filter { $0.isNumber }
                        ghinNumber = String(filtered.prefix(8))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.borderLight, lineWidth: 1)
                    )

                // Placeholder text removed for App Store compliance
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(.white)
        .onAppear {
            ghinNumber = authService.currentUser?.ghinNumber ?? ""
        }
        .alert("Update Failed", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
    }

    private func saveGhin() {
        isSaving = true
        let value = ghinNumber.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                try await authService.updateProfile(ProfileUpdate(
                    ghinNumber: value.isEmpty ? nil : value
                ))
                isSaving = false
                ToastManager.shared.success("GHIN number updated")
                dismiss()
            } catch {
                isSaving = false
                errorMessage = "Could not update GHIN number. Please try again."
                showError = true
            }
        }
    }
}

// MARK: - Club Edit Sheet

struct ClubEditSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @FocusState private var isClubSearchFocused: Bool
    @State private var searchResults: [GolfCourseResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedClub: GolfCourseResult? = nil
    @State private var isClubMember = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundColor(Color.textTertiary)

                Spacer()

                Text("Home Course")
                    .font(.carry.headline)
                    .foregroundColor(Color.pureBlack)

                Spacer()

                Button("Save") { saveClub() }
                    .font(.carry.bodyLGSemibold)
                    .foregroundColor(isSaving ? Color.textDisabled : Color.textPrimary)
                    .disabled(isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Home Course header
                    Text("Home Course")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    if let club = selectedClub {
                        // Selected club — "Change" button pattern
                        Button {
                            selectedClub = nil
                            searchText = ""
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(club.clubName ?? club.courseName ?? "Golf Club")
                                        .font(.carry.bodySemibold)
                                        .foregroundColor(Color.textPrimary)
                                    if !club.locationLabel.isEmpty {
                                        Text(club.locationLabel)
                                            .font(.system(size: 13))
                                            .foregroundColor(Color.textTertiary)
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
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.borderLight, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Search field
                        HStack(spacing: 8) {
                            if isSearching {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.textDisabled)
                            }

                            TextField("Search golf clubs", text: $searchText)
                                .font(.system(size: 16))
                                .focused($isClubSearchFocused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: searchText) {
                                    debounceSearch(searchText)
                                }

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                    searchResults = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.textDisabled)
                                }
                                .accessibilityLabel("Clear search")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isClubSearchFocused ? Color(hexString: "#333333") : Color.borderLight, lineWidth: isClubSearchFocused ? 1.5 : 1)
                        )
                        .animation(.easeOut(duration: 0.15), value: isClubSearchFocused)

                        // Search results
                        if !searchResults.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(searchResults.prefix(5)) { course in
                                    Button {
                                        selectedClub = course
                                        searchText = ""
                                        searchResults = []
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(course.clubName ?? course.courseName ?? "Golf Club")
                                                .font(.carry.body)
                                                .foregroundColor(Color.textPrimary)
                                            if !course.locationLabel.isEmpty {
                                                Text(course.locationLabel)
                                                    .font(.system(size: 13))
                                                    .foregroundColor(Color.textTertiary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)

                                    if course.id != searchResults.prefix(5).last?.id {
                                        Rectangle()
                                            .fill(Color.bgPrimary)
                                            .frame(height: 1)
                                            .padding(.leading, 16)
                                    }
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.borderLight, lineWidth: 1)
                            )
                        }
                    }

                    // Membership radio buttons — shown after course is selected
                    if selectedClub != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Membership")
                                .font(.carry.bodySMBold)
                                .foregroundColor(Color.textPrimary)
                                .padding(.leading, 4)

                            MembershipRadioButton(
                                label: "Club Member",
                                subtitle: "I'm a member at this course",
                                isSelected: isClubMember
                            ) {
                                withAnimation(.easeOut(duration: 0.15)) { isClubMember = true }
                            }

                            MembershipRadioButton(
                                label: "Home Course Only",
                                subtitle: "I play here regularly but I'm not a member",
                                isSelected: !isClubMember
                            ) {
                                withAnimation(.easeOut(duration: 0.15)) { isClubMember = false }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.bgSecondary)
        .onAppear {
            // Pre-fill membership from current profile
            isClubMember = authService.currentUser?.isClubMember ?? true
        }
        .alert("Update Failed", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
    }

    private func debounceSearch(_ query: String) {
        searchTask?.cancel()

        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }

            do {
                let results = try await GolfCourseService.shared.searchCourses(query: query)
                guard !Task.isCancelled else { return }
                searchResults = results
            } catch {
                guard !Task.isCancelled else { return }
                searchResults = []
            }
            isSearching = false
        }
    }

    private func saveClub() {
        isSaving = true
        let clubName = selectedClub?.clubName ?? selectedClub?.courseName
        let clubId = selectedClub?.id

        Task {
            do {
                try await authService.updateProfile(ProfileUpdate(
                    homeClub: clubName,
                    homeClubId: clubId,
                    isClubMember: isClubMember
                ))
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorMessage = "Could not update home club. Please try again."
                showError = true
            }
        }
    }

}

// MARK: - Share Sheet

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Notifications Sheet

struct NotificationsSheet: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("notif_gameAlerts") private var gameAlerts = true
    @AppStorage("notif_liveScoring") private var liveScoring = true
    @AppStorage("notif_groupActivity") private var groupActivity = true

    var body: some View {
        VStack(spacing: 0) {
            Text("Notifications")
                .font(.carry.labelBold)
                .foregroundColor(Color.textPrimary)
                .padding(.top, 40)
                .padding(.bottom, 20)

            // Game Alerts toggle
            notifToggle(
                title: "Game Alerts",
                subtitle: "Invites, round start & end, scorer assignment",
                isOn: $gameAlerts
            )

            notifDivider

            // Live Scoring toggle
            notifToggle(
                title: "Live Scoring",
                subtitle: "Skins won during a round, all groups active",
                isOn: $liveScoring
            )

            notifDivider

            // Group Activity toggle
            notifToggle(
                title: "Group Activity",
                subtitle: "Members joining or declining, score disputes, tee time reminders",
                isOn: $groupActivity
            )

            notifDivider

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Push notifications require permission in ")
                    + Text("iOS Settings").underline()
            }
            .font(.carry.caption)
            .foregroundColor(Color.textSecondary)
            .padding(.top, 12)
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private func notifToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.carry.body)
                    .foregroundColor(Color.textPrimary)
                Text(subtitle)
                    .font(.carry.caption)
                    .foregroundColor(Color.textSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var notifDivider: some View {
        Rectangle()
            .fill(Color.bgPrimary)
            .frame(height: 1)
            .padding(.horizontal, 20)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("1 - New user (no profile)") {
    ProfileView(skinGameGroups: .constant([]))
        .environmentObject(AuthService())
        .environmentObject(StoreService())
}

#Preview("2 - Populated profile") {
    let auth = AuthService()
    auth.currentUser = ProfileDTO(
        id: UUID(),
        firstName: "Daniel",
        lastName: "Sigvardsson",
        username: nil,
        displayName: "Daniel",
        initials: "DS",
        color: "#D4A017",
        avatar: "🏌️",
        handicap: 12.4,
        ghinNumber: "1234567",
        homeClub: "Pine Valley Golf Club",
        homeClubId: 12345,
        email: "daniel@example.com",
        createdAt: nil,
        updatedAt: nil
    )
    return ProfileView(skinGameGroups: .constant(SavedGroup.demo))
        .environmentObject(auth)
        .environmentObject(StoreService())
}
#endif
