import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService

    enum Tab {
        case home, skinGames, profile
    }

    @State private var selectedTab: Tab = .home

    var body: some View {
        VStack(spacing: 0) {
            // Tab content
            Group {
                switch selectedTab {
                case .home:
                    HomeView()
                case .skinGames:
                    GroupsListView()
                case .profile:
                    ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar
            tabBar
        }
        .onAppear {
            // Auto-navigate to profile for new users
            if authService.isNewUser {
                selectedTab = .profile
                authService.isNewUser = false
            }
        }
    }

    // MARK: - Custom Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(icon: "house.fill", label: "Home", isSelected: selectedTab == .home) {
                selectedTab = .home
            }

            tabButton(icon: "person.3.fill", label: "Skin Games", isSelected: selectedTab == .skinGames) {
                selectedTab = .skinGames
            }

            tabButton(icon: "person.crop.circle", label: "Profile", isSelected: selectedTab == .profile) {
                selectedTab = .profile
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 20)
        .background(
            Rectangle()
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 8, y: -4)
                .ignoresSafeArea(.container, edges: .bottom)
        )
    }

    private func tabButton(icon: String, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? Color(hex: "#C4A450") : Color(hex: "#999999"))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? Color(hex: "#C4A450") : Color(hex: "#999999"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
