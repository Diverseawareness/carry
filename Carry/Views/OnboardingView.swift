import SwiftUI
import PhotosUI
import UserNotifications

struct OnboardingView: View {
    @EnvironmentObject var authService: AuthService
    var onComplete: (() -> Void)? = nil
    var initialStep: Int = 0
    @State private var step = 0
    @State private var firstName = ""
    @State private var lastName = ""
    // username fields removed — hidden for now
    @State private var ghinNumber = ""
    @State private var handicapText = ""
    enum OBField: Hashable { case firstName, lastName, clubSearch, ghinNumber, handicap }
    @FocusState private var obFocused: OBField?
    @State private var didPreFill = false
    @State private var hasAppleName = false
    @State private var progressReady = false

    // Photo picker
    @State private var selectedPhoto: UIImage? = nil
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photoCropImage: UIImage? = nil  // image awaiting crop
    @State private var showPhotoOptions = false
    @State private var showCamera = false

    // Golf club
    @State private var clubSearchText = ""
    @State private var clubSearchResults: [GolfCourseResult] = []
    @State private var isClubSearching = false
    @State private var clubSearchTask: Task<Void, Never>?
    @State private var selectedClub: GolfCourseResult? = nil
    @State private var isClubMember = true   // default: Club Member selected

    private var totalSteps: Int { hasAppleName ? 2 : 3 }
    private var isGolfProfileStep: Bool {
        hasAppleName ? step == 0 : step == 1
    }


    /// Filter handicap text: digits + one decimal, max 1 decimal place, capped at 54.0
    /// Allows 0…54.0 or +0.1…+10.0 (plus handicap) with one decimal place.
    /// In golf, "+2.5" means better-than-scratch — stored as -2.5 internally.
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
                filtered.append(".")  // normalize comma to dot
            } else if ch.isNumber {
                if hasDecimal {
                    guard decimalDigits < 1 else { continue }
                    filtered.append(ch)
                    decimalDigits += 1
                } else {
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

    /// Parses handicap text to Double. "+5.2" → -5.2 (plus handicap stored negative).
    private func parseHandicap(_ text: String) -> Double {
        if text.hasPrefix("+") {
            return -(Double(String(text.dropFirst())) ?? 0.0)
        }
        return Double(text) ?? 0.0
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(progressReady && i <= step ? Color.textPrimary : Color.borderSubtle)
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .animation(.easeOut(duration: 0.3), value: step)
                .animation(.easeOut(duration: 0.4), value: progressReady)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step + 1) of \(totalSteps)")
                .accessibilityValue("\(Int(Double(step + 1) / Double(totalSteps) * 100)) percent complete")

                Spacer()
                    .frame(height: 56)

                // Step content — adapts based on whether Apple provided the name
                Group {
                    if hasAppleName {
                        // Apple gave us the name: skip name fields
                        switch step {
                        case 0: golfProfileStep
                        case 1: notificationStep
                        default: EmptyView()
                        }
                    } else {
                        // No name from Apple: ask for name first
                        switch step {
                        case 0: nameStep
                        case 1: golfProfileStep
                        case 2: notificationStep
                        default: EmptyView()
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                // Bottom button bar — hidden on golf profile step (button is inline there)
                if !isGolfProfileStep {
                    buttonBar
                        .padding(.bottom, 24)
                }
            }

            // Full-screen crop overlay
            if let cropImage = photoCropImage {
                ImageCropView(
                    image: cropImage,
                    onSave: { cropped in
                        selectedPhoto = cropped
                        withAnimation(.easeOut(duration: 0.2)) {
                            photoCropImage = nil
                        }
                    },
                    onCancel: {
                        photoItem = nil
                        withAnimation(.easeOut(duration: 0.2)) {
                            photoCropImage = nil
                        }
                    }
                )
                .transition(.opacity)
                .ignoresSafeArea()
            }
        }
        .onAppear {
            guard !didPreFill else { return }
            didPreFill = true
            // Pre-fill names from Apple Sign In profile
            if let profile = authService.currentUser {
                if !profile.firstName.isEmpty {
                    firstName = profile.firstName
                    lastName = profile.lastName
                    hasAppleName = true
                } else if !profile.displayName.isEmpty && profile.displayName != "Player" {
                    let parts = profile.displayName.split(separator: " ", maxSplits: 1)
                    firstName = String(parts.first ?? "")
                    lastName = parts.count > 1 ? String(parts.last ?? "") : ""
                    hasAppleName = !firstName.isEmpty
                }
            }
            if initialStep > 0 {
                step = initialStep
            }
            // Animate first progress bar filling after slide-in settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                progressReady = true
            }
        }
    }

    // MARK: - Button Bar

    private let btnRadius: CGFloat = 14

    private var buttonBar: some View {
        HStack(spacing: 12) {
            // Left button (Skip / Back)
            if step == 0 || step == totalSteps - 1 {
                // First step and notification step — no back needed
                EmptyView()
            } else {
                // Back button
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { step -= 1 }
                } label: {
                    Text("Back")
                        .font(.carry.headline)
                        .foregroundColor(Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: btnRadius).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: btnRadius).strokeBorder(Color.borderSubtle, lineWidth: 1.5))
                }
            }

            // Right button (Next / Enable Notifications)
            Button {
                if step == totalSteps - 1 {
                    // Request permission — auto-advance when alert is dismissed
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                        DispatchQueue.main.async {
                            advance()
                        }
                    }
                } else {
                    advance()
                }
            } label: {
                Text(step == totalSteps - 1 ? "Enable Notifications" : "Next")
                    .font(.carry.headlineBold)
                    .foregroundColor(continueEnabled ? .white : Color.textDisabled)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: btnRadius)
                            .fill(continueEnabled ? Color.textPrimary : Color.borderSubtle)
                    )
            }
            .disabled(!continueEnabled)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Logic

    private var continueEnabled: Bool {
        if hasAppleName {
            // Flow: Golf Profile → Notifications
            switch step {
            case 0:
                let hasClub = selectedClub != nil
                let hasHandicap = !handicapText.trimmingCharacters(in: .whitespaces).isEmpty
                return hasClub && hasHandicap
            case 1: return true  // notifications
            default: return true
            }
        } else {
            // Flow: Name → Golf Profile → Notifications
            switch step {
            case 0:
                let hasFirst = !firstName.trimmingCharacters(in: .whitespaces).isEmpty
                let hasLast = !lastName.trimmingCharacters(in: .whitespaces).isEmpty
                return hasFirst && hasLast
            case 1:
                let hasClub = selectedClub != nil
                let hasHandicap = !handicapText.trimmingCharacters(in: .whitespaces).isEmpty
                return hasClub && hasHandicap
            case 2: return true  // notifications
            default: return true
            }
        }
    }

    private func advance() {
        if step < totalSteps - 1 {
            withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
        } else {
            finishOnboarding()
        }
    }

    private func finishOnboarding() {
        authService.completeOnboarding(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            username: nil,
            ghinNumber: ghinNumber.isEmpty ? nil : ghinNumber,
            handicap: parseHandicap(handicapText),
            photo: selectedPhoto,
            homeClub: selectedClub?.clubName ?? selectedClub?.courseName,
            homeClubId: selectedClub?.id,
            isClubMember: isClubMember
        )
        let name = firstName.trimmingCharacters(in: .whitespaces)
        ToastManager.shared.success("Account created, welcome \(name)!")
        Analytics.onboardingCompleted()
        onComplete?()
    }

    // MARK: - Step: Name only (no Apple name)

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's your name?")
                .font(.carry.pageTitle)
                .foregroundColor(Color.textPrimary)

            Text("This is how you'll appear to other players.")
                .font(.system(size: 15))
                .foregroundColor(Color.textTertiary)
                .padding(.bottom, 8)

            // First Name
            VStack(alignment: .leading, spacing: 6) {
                Text("First Name")
                    .font(.carry.bodySMBold)
                    .foregroundColor(Color.textPrimary)
                    .padding(.leading, 4)

                TextField("First name", text: $firstName)
                    .font(.system(size: 16))
                    .textContentType(.givenName)
                    .submitLabel(.next)
                    .focused($obFocused, equals: .firstName)
                    .onSubmit { obFocused = .lastName }
                    .carryInput(focused: obFocused == .firstName)
            }

            // Last Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Last Name")
                    .font(.carry.bodySMBold)
                    .foregroundColor(Color.textPrimary)
                    .padding(.leading, 4)

                TextField("Last name", text: $lastName)
                    .font(.system(size: 16))
                    .textContentType(.familyName)
                    .submitLabel(.done)
                    .focused($obFocused, equals: .lastName)
                    .onSubmit { obFocused = nil }
                    .carryInput(focused: obFocused == .lastName)
            }
        }
        .padding(.horizontal, 24)
        .onTapGesture { obFocused = nil }
    }

    // MARK: - Step: Golf Profile (Club + Index + GHIN)

    private var golfProfileStep: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Golf Profile")
                    .font(.carry.pageTitle)
                    .foregroundColor(Color.textPrimary)

                Text("Help us set up your skins games.")
                    .font(.system(size: 15))
                    .foregroundColor(Color.textTertiary)
                    .padding(.bottom, 8)

                // Home Course
                clubSection
                    .id("clubSection")

                // Handicap Index
                VStack(alignment: .leading, spacing: 6) {
                    Text("Handicap Index")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.leading, 4)

                    TextField("e.g. 12.4", text: $handicapText)
                        .font(.system(size: 16))
                        .focused($obFocused, equals: .handicap)
                        .keyboardType(.decimalPad)
                        .onChange(of: handicapText) {
                            let filtered = filterHandicap(handicapText)
                            if filtered != handicapText {
                                DispatchQueue.main.async {
                                    handicapText = filtered
                                }
                            }
                        }
                        .carryInput(focused: obFocused == .handicap)
                }
                .id("handicapSection")

                // GHIN Number
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("GHIN Number")
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.textPrimary)
                    }
                    .padding(.leading, 4)

                    TextField("e.g. 1234567", text: $ghinNumber)
                        .font(.system(size: 16))
                        .focused($obFocused, equals: .ghinNumber)
                        .keyboardType(.numberPad)
                        .onChange(of: ghinNumber) {
                            let filtered = ghinNumber.filter { $0.isNumber }
                            ghinNumber = String(filtered.prefix(8))
                        }
                        .carryInput(focused: obFocused == .ghinNumber)
                }
                .id("ghinSection")

                Text("*GHIN number is optional and used for handicap verification.")
                    .font(.system(size: 12))
                    .foregroundColor(Color.textTertiary)
                    .padding(.top, 4)

                // Next button inline (not anchored above keyboard)
                Button {
                    advance()
                } label: {
                    Text("Next")
                        .font(.carry.headlineBold)
                        .foregroundColor(continueEnabled ? .white : Color.textDisabled)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: btnRadius)
                                .fill(continueEnabled ? Color.textPrimary : Color.borderSubtle)
                        )
                }
                .disabled(!continueEnabled)
                .padding(.top, 24)
                .id("nextButton")

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { obFocused = nil }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { obFocused = nil }
                    .font(.carry.bodySemibold)
            }
        }
        .onChange(of: clubSearchText) {
            if !clubSearchText.isEmpty {
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("clubSection", anchor: .top)
                }
            }
        }
        .onChange(of: obFocused) { _, field in
            switch field {
            case .clubSearch:
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("clubSection", anchor: .top)
                }
            case .handicap:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("handicapSection", anchor: .center)
                    }
                }
            case .ghinNumber:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("ghinSection", anchor: .center)
                    }
                }
            default: break
            }
        }
        }
    }

    // MARK: - Club Section

    private var clubSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Home Course")
                .font(.carry.bodySMBold)
                .foregroundColor(Color.textPrimary)
                .padding(.leading, 4)

                if let club = selectedClub {
                    // Selected club — "Change" button pattern (matches GroupsListView)
                    Button {
                        selectedClub = nil
                        clubSearchText = ""
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
                        if isClubSearching {
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
                            .focused($obFocused, equals: .clubSearch)
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
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(obFocused == .clubSearch ? Color(hexString: "#333333") : Color.borderLight, lineWidth: obFocused == .clubSearch ? 1.5 : 1)
                    )
                    .animation(.easeOut(duration: 0.15), value: obFocused)

                    // Search results
                    if clubSearchResults.isEmpty && clubSearchText.count >= 2 && !isClubSearching {
                        VStack(spacing: 4) {
                            Text("No clubs found")
                                .font(.carry.bodySM)
                                .foregroundColor(Color.textDisabled)
                            Text("Check the spelling or try a different name")
                                .font(.carry.caption)
                                .foregroundColor(Color.borderLight)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else if !clubSearchResults.isEmpty {
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
    }

    // MARK: - Club Search

    private func debounceClubSearch(_ query: String) {
        clubSearchTask?.cancel()

        guard query.count >= 2 else {
            clubSearchResults = []
            isClubSearching = false
            return
        }

        isClubSearching = true

        clubSearchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms debounce
            guard !Task.isCancelled else { return }

            do {
                let results = try await GolfCourseService.shared.searchCourses(query: query)
                guard !Task.isCancelled else { return }
                clubSearchResults = results
            } catch {
                guard !Task.isCancelled else { return }
                clubSearchResults = []
            }
            isClubSearching = false
        }
    }

    // MARK: - Step: Notifications

    @State private var notificationsEnabled = false
    @State private var notifShowTitle = false
    @State private var notifShowCard = false
    @State private var notifShowBenefits = [false, false, false]

    private var notificationStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // Title
            Text("Stay in the game")
                .font(.system(size: 27, weight: .semibold))
                .foregroundColor(Color.deepNavy)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 24)
                .opacity(notifShowTitle ? 1 : 0)
                .offset(y: notifShowTitle ? 0 : 20)

            // Mock notification preview card
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.successBgLight)
                        .frame(width: 38, height: 38)
                    Text("$")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hexString: "#1B7A14"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tee time in 5 minutes")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hexString: "#2A2A2A"))
                    Text("Start Friday Meeting so your players can join the scorecard.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hexString: "#2A2A2A"))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.05), radius: 7, y: 11)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color(hexString: "#DADADA"), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .opacity(notifShowCard ? 1 : 0)
            .offset(y: notifShowCard ? 0 : 24)

            // Benefits
            VStack(alignment: .leading, spacing: 24) {
                notificationBenefit("Tee time reminders before your round")
                    .opacity(notifShowBenefits[0] ? 1 : 0)
                    .offset(y: notifShowBenefits[0] ? 0 : 16)
                notificationBenefit("Know when your game goes LIVE")
                    .opacity(notifShowBenefits[1] ? 1 : 0)
                    .offset(y: notifShowBenefits[1] ? 0 : 16)
                notificationBenefit("See when skins are won in real time")
                    .opacity(notifShowBenefits[2] ? 1 : 0)
                    .offset(y: notifShowBenefits[2] ? 0 : 16)
            }
            .padding(.horizontal, 42)

            Spacer()
        }
        .onAppear { staggerNotifAnimations() }
    }

    private func staggerNotifAnimations() {
        // Wait for the slide-in transition to finish before animating content
        let baseDelay: Double = 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay) {
            withAnimation(.easeOut(duration: 0.35)) { notifShowTitle = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + 0.1) {
            withAnimation(.easeOut(duration: 0.35)) { notifShowCard = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + 0.25) {
            withAnimation(.easeOut(duration: 0.3)) { notifShowBenefits[0] = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + 0.35) {
            withAnimation(.easeOut(duration: 0.3)) { notifShowBenefits[1] = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + 0.45) {
            withAnimation(.easeOut(duration: 0.3)) { notifShowBenefits[2] = true }
        }
    }

    private func notificationBenefit(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.successBgLight)
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hexString: "#1B7A14"))
            }
            Text(text)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Color(hexString: "#2A2A2A"))
                .tracking(-0.23)
        }
    }
}
