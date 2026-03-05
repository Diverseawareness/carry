import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var authService: AuthService
    @State private var step = 0
    @State private var name = ""
    @State private var selectedColor = "#D4A017"
    @State private var selectedAvatar = "🏌️"
    @State private var ghinNumber = ""
    @State private var handicapText = ""
    @State private var didPreFill = false

    private let totalSteps = 4

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
        ZStack {
            Color(hex: "#F0F0F0").ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i <= step ? Color(hex: "#1B5E20") : Color(hex: "#DCDCDC"))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 60)
                .padding(.bottom, 40)

                // Step content
                Group {
                    switch step {
                    case 0: nameStep
                    case 1: avatarStep
                    case 2: handicapStep
                    case 3: readyStep
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                // Navigation buttons
                VStack(spacing: 12) {
                    // Continue / Finish button
                    Button {
                        advance()
                    } label: {
                        Text(step == totalSteps - 1 ? "Set Up Game" : "Continue")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(continueEnabled
                                          ? Color(hex: "#1B5E20")
                                          : Color(hex: "#CCCCCC"))
                            )
                    }
                    .disabled(!continueEnabled)
                    .padding(.horizontal, 40)

                    // Back / Skip
                    if step > 0 && step < totalSteps - 1 {
                        HStack(spacing: 32) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) { step -= 1 }
                            } label: {
                                Text("Back")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "#999999"))
                            }

                            if step == 2 {
                                Button {
                                    // Skip handicap entry
                                    withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
                                } label: {
                                    Text("Skip")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(hex: "#BBBBBB"))
                                }
                            }
                        }
                        .padding(.top, 4)
                    } else if step == 0 {
                        // No back on first step, but show spacer for layout
                        Color.clear.frame(height: 20)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            guard !didPreFill else { return }
            didPreFill = true
            // Pre-fill name from Apple Sign-In profile
            if let profile = authService.currentUser {
                let appleName = profile.displayName
                if !appleName.isEmpty && appleName != "Player" {
                    name = appleName
                    // Skip name step — go straight to avatar
                    step = 1
                }
            }
        }
    }

    private var continueEnabled: Bool {
        switch step {
        case 0: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return true  // avatar has default
        case 2: return true  // handicap is optional
        case 3: return true
        default: return true
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
            name: name.trimmingCharacters(in: .whitespaces),
            color: selectedColor,
            avatar: selectedAvatar,
            ghinNumber: ghinNumber.isEmpty ? nil : ghinNumber,
            handicap: Double(handicapText) ?? 0.0
        )
    }

    // MARK: - Step 1: Name

    private var nameStep: some View {
        VStack(spacing: 20) {
            Text("What should we\ncall you?")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(Color(hex: "#1A1A1A"))

            Text("This is how you'll appear to other players.")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#999999"))

            TextField("Your name", text: $name)
                .font(.system(size: 18))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(hex: "#E0E0E0"), lineWidth: 1)
                )
                .padding(.horizontal, 50)
                .padding(.top, 8)

            // Color picker
            VStack(spacing: 10) {
                Text("PICK YOUR COLOR")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(Color(hex: "#BBBBBB"))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                    ForEach(colorOptions, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 36, height: 36)
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
                .padding(.horizontal, 40)
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Step 2: Avatar

    private var avatarStep: some View {
        VStack(spacing: 20) {
            // Live preview
            ZStack {
                Circle()
                    .fill(Color(hex: selectedColor).opacity(0.09))
                Circle()
                    .strokeBorder(Color(hex: selectedColor).opacity(0.25), lineWidth: 2)
                Text(selectedAvatar)
                    .font(.system(size: 36))
            }
            .frame(width: 72, height: 72)

            Text("Pick your look")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            Text("Choose an emoji that represents you on the course.")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#999999"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Emoji grid
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
            .padding(.horizontal, 30)
            .padding(.top, 8)
        }
    }

    // MARK: - Step 3: Handicap

    private var handicapStep: some View {
        VStack(spacing: 20) {
            Text("Your handicap")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            Text("Used to calculate strokes in skins games.")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#999999"))

            // GHIN number field
            VStack(alignment: .leading, spacing: 6) {
                Text("GHIN NUMBER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(Color(hex: "#BBBBBB"))
                    .padding(.leading, 4)

                TextField("Optional", text: $ghinNumber)
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
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)

            // Handicap index field
            VStack(alignment: .leading, spacing: 6) {
                Text("HANDICAP INDEX")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(Color(hex: "#BBBBBB"))
                    .padding(.leading, 4)

                TextField("e.g. 12.4", text: $handicapText)
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
            .padding(.horizontal, 40)

            Text("You can always update this later in settings.")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#CCCCCC"))
                .padding(.top, 4)
        }
    }

    // MARK: - Step 4: Ready

    private var readyStep: some View {
        VStack(spacing: 24) {
            // Player card preview
            ZStack {
                Circle()
                    .fill(Color(hex: selectedColor).opacity(0.09))
                Circle()
                    .strokeBorder(Color(hex: selectedColor).opacity(0.25), lineWidth: 2)
                Text(selectedAvatar)
                    .font(.system(size: 44))
            }
            .frame(width: 88, height: 88)

            Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Player" : name.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(hex: "#1A1A1A"))

            // Stats
            VStack(spacing: 12) {
                if !handicapText.isEmpty, let hcp = Double(handicapText) {
                    detailRow(label: "Handicap Index", value: String(format: "%.1f", hcp))
                }
                if !ghinNumber.isEmpty {
                    detailRow(label: "GHIN", value: ghinNumber)
                }
            }
            .padding(.horizontal, 60)

            Text("You're all set.")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "#999999"))
                .padding(.top, 8)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#999999"))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "#1A1A1A"))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white)
        )
    }
}
