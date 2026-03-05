import SwiftUI

struct SplashShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = w / 2
        let cy = h / 2

        // Organic splash shape - irregular blob with protrusions
        path.move(to: CGPoint(x: cx + w*0.08, y: cy - h*0.42))
        path.addQuadCurve(to: CGPoint(x: cx + w*0.35, y: cy - h*0.25),
                          control: CGPoint(x: cx + w*0.30, y: cy - h*0.45))
        path.addQuadCurve(to: CGPoint(x: cx + w*0.42, y: cy + h*0.05),
                          control: CGPoint(x: cx + w*0.48, y: cy - h*0.10))
        path.addQuadCurve(to: CGPoint(x: cx + w*0.25, y: cy + h*0.35),
                          control: CGPoint(x: cx + w*0.30, y: cy + h*0.30))
        path.addQuadCurve(to: CGPoint(x: cx - w*0.05, y: cy + h*0.42),
                          control: CGPoint(x: cx + w*0.10, y: cy + h*0.48))
        path.addQuadCurve(to: CGPoint(x: cx - w*0.35, y: cy + h*0.20),
                          control: CGPoint(x: cx - w*0.25, y: cy + h*0.45))
        path.addQuadCurve(to: CGPoint(x: cx - w*0.40, y: cy - h*0.15),
                          control: CGPoint(x: cx - w*0.48, y: cy + h*0.02))
        path.addQuadCurve(to: CGPoint(x: cx - w*0.15, y: cy - h*0.38),
                          control: CGPoint(x: cx - w*0.38, y: cy - h*0.35))
        path.addQuadCurve(to: CGPoint(x: cx + w*0.08, y: cy - h*0.42),
                          control: CGPoint(x: cx + w*0.02, y: cy - h*0.48))
        path.closeSubpath()

        return path
    }
}

// Convenience view for splashed/squashed skins
struct SplashIcon: View {
    var size: CGFloat = 16
    var color: Color = Color(hex: "#CCCCCC")

    var body: some View {
        Image("squash")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(color)
            .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            SplashIcon(size: 24, color: Color(hex: "#FF5733"))
            SplashIcon(size: 32, color: Color(hex: "#3366FF"))
            SplashIcon(size: 40, color: Color(hex: "#33FF66"))
        }

        // Show the shape with different colors
        HStack(spacing: 20) {
            SplashShape()
                .fill(Color(hex: "#FFD700"))
                .frame(width: 50, height: 50)

            SplashShape()
                .fill(Color(hex: "#FF1493"))
                .frame(width: 50, height: 50)

            SplashShape()
                .stroke(Color(hex: "#00CED1"), lineWidth: 2)
                .frame(width: 50, height: 50)
        }
    }
    .padding()
}
