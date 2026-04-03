import SwiftUI

/// The Venmo "V" logo as a SwiftUI Shape, rendered from the official SVG path.
/// Original viewBox: 0 0 36 38
struct VenmoLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 36.0
        let sy = rect.height / 38.0
        var p = Path()
        p.move(to: CGPoint(x: 33.471 * sx, y: 0 * sy))
        p.addCurve(
            to: CGPoint(x: 35.4654 * sx, y: 7.56589 * sy),
            control1: CGPoint(x: 34.8477 * sx, y: 2.26977 * sy),
            control2: CGPoint(x: 35.4654 * sx, y: 4.61023 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 20.8893 * sx, y: 37.8295 * sy),
            control1: CGPoint(x: 35.4654 * sx, y: 16.9922 * sy),
            control2: CGPoint(x: 27.4195 * sx, y: 29.2341 * sy)
        )
        p.addLine(to: CGPoint(x: 5.97829 * sx, y: 37.8295 * sy))
        p.addLine(to: CGPoint(x: 0 * sx, y: 2.06512 * sy))
        p.addLine(to: CGPoint(x: 13.0605 * sx, y: 0.824805 * sy))
        p.addLine(to: CGPoint(x: 16.2357 * sx, y: 26.2722 * sy))
        p.addCurve(
            to: CGPoint(x: 22.8378 * sx, y: 8.73674 * sy),
            control1: CGPoint(x: 19.1876 * sx, y: 21.4574 * sy),
            control2: CGPoint(x: 22.8378 * sx, y: 13.8915 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 21.5975 * sx, y: 2.41116 * sy),
            control1: CGPoint(x: 22.8378 * sx, y: 5.91256 * sy),
            control2: CGPoint(x: 22.3541 * sx, y: 3.99256 * sy)
        )
        p.addLine(to: CGPoint(x: 33.471 * sx, y: 0 * sy))
        p.closeSubpath()
        return p
    }
}

/// Convenience view that renders the Venmo logo filled with a given color.
struct VenmoLogo: View {
    var color: Color = Color.venmoBlue
    var size: CGFloat = 17

    var body: some View {
        VenmoLogoShape()
            .fill(color)
            .frame(width: size * (36.0 / 38.0), height: size)
    }
}
