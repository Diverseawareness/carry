import SwiftUI

struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            Color.successBgLight
                .ignoresSafeArea()

            Image("carry-glyph")
                .resizable()
                .scaledToFit()
                .frame(width: 105, height: 96)
        }
    }
}
