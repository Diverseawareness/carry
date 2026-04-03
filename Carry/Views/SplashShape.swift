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

// Convenience view for splashed/squashed skins — simple diagonal line
struct SplashIcon: View {
    var size: CGFloat = 16
    var color: Color = Color.borderMedium

    var body: some View {
        DiagonalLine()
            .stroke(color, style: StrokeStyle(lineWidth: max(1.5, size * 0.08), lineCap: .round))
            .frame(width: size, height: size)
    }
}

private struct DiagonalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = rect.width * 0.15
        path.move(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            SplashIcon(size: 24, color: Color(hexString: "#FF5733"))
            SplashIcon(size: 32, color: Color(hexString: "#3366FF"))
            SplashIcon(size: 40, color: Color(hexString: "#33FF66"))
        }

        // Show the shape with different colors
        HStack(spacing: 20) {
            SplashShape()
                .fill(Color.goldStandard)
                .frame(width: 50, height: 50)

            SplashShape()
                .fill(Color(hexString: "#FF1493"))
                .frame(width: 50, height: 50)

            SplashShape()
                .stroke(Color(hexString: "#00CED1"), lineWidth: 2)
                .frame(width: 50, height: 50)
        }
    }
    .padding()
}
