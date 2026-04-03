import SwiftUI

/// Top-down golf ball rolling around cup lip with gravity-based speed.
/// Slow at top of arc, fast at bottom — dramatic "will it drop?" feel.
struct GolfBallLoader: View {
    var size: CGFloat = 60

    private var cupR: CGFloat { size * 0.22 }
    private var rimW: CGFloat { size * 0.08 }
    private var ballR: CGFloat { size * 0.12 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                drawScene(context: context, size: canvasSize, time: now)
            }
        }
        .frame(width: size, height: size)
    }

    private func drawScene(context: GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let cy = size.height / 2
        let center = CGPoint(x: cx, y: cy)

        // Draw cup
        drawDisc(ctx: context, at: center, r: cupR + rimW, color: Color(hexString: "#D4D4D4"))
        drawDisc(ctx: context, at: center, r: cupR + rimW * 0.3, color: Color(hexString: "#C8C8C8"))
        drawDisc(ctx: context, at: center, r: cupR, color: Color.textPrimary)
        drawDisc(ctx: context, at: center, r: cupR * 0.6, color: Color(hexString: "#131313"))
        drawDisc(ctx: context, at: center, r: self.size * 0.02, color: Color(hexString: "#2E2E2E"))

        // Animation timing
        // Cycle: 4.5s total
        // 0–3.2s: gravity orbit (slow top, fast bottom), ~1.5 loops
        // 3.2–3.8s: spiral + drop
        // 3.8–4.5s: pause
        let cycle: Double = 4.5
        let t = time.truncatingRemainder(dividingBy: cycle)

        if t < 3.2 {
            drawGravityBall(ctx: context, center: center, t: t)
        } else if t < 3.8 {
            drawDropBall(ctx: context, center: center, t: t)
        }
    }

    private func drawGravityBall(ctx: GraphicsContext, center: CGPoint, t: Double) {
        let progress = t / 3.2 // 0→1
        let loops: Double = 1.6
        let rawAngle = progress * loops * .pi * 2

        // Gravity effect: ball nearly stops at top, whips through bottom
        // Higher strength = more dramatic speed variation
        let gravityStrength: Double = 0.7
        let gravityAngle = rawAngle + gravityStrength * sin(rawAngle) + 0.15 * sin(rawAngle * 2)

        // Start from top (12 o'clock = -π/2)
        let angle = gravityAngle - .pi / 2

        // Orbit tightens slightly over time
        let tighten = 1.0 - progress * 0.12
        let lipR = (cupR + rimW * 0.45) * tighten

        let bx = center.x + cos(angle) * lipR
        let by = center.y + sin(angle) * lipR

        // Shadow toward cup center
        let shadowDist = ballR * 0.25
        let dx = (center.x - bx)
        let dy = (center.y - by)
        let dist = sqrt(dx * dx + dy * dy)
        let nx = dx / max(dist, 1)
        let ny = dy / max(dist, 1)
        let sp = CGPoint(x: bx + nx * shadowDist, y: by + ny * shadowDist)
        drawDisc(ctx: ctx, at: sp, r: ballR * 0.7, color: Color.black.opacity(0.14))

        // Ball
        drawDisc(ctx: ctx, at: CGPoint(x: bx, y: by), r: ballR, color: .white)
        strokeCircle(ctx: ctx, at: CGPoint(x: bx, y: by), r: ballR, color: Color.bgLight, width: 0.5)

        // Dimples
        let dR = ballR * 0.09
        drawDisc(ctx: ctx, at: CGPoint(x: bx - ballR * 0.25, y: by - ballR * 0.25), r: dR, color: Color(hexString: "#E4E4E4"))
        drawDisc(ctx: ctx, at: CGPoint(x: bx + ballR * 0.15, y: by - ballR * 0.1), r: dR * 0.8, color: Color(hexString: "#E8E8E8"))
    }

    private func drawDropBall(ctx: GraphicsContext, center: CGPoint, t: Double) {
        let dt = (t - 3.2) / 0.6 // 0→1
        let ease = dt * dt * dt // cubic ease in

        let lipR = (cupR + rimW * 0.45) * 0.88
        let curR = lipR * (1.0 - ease * 0.95)

        // Continue spinning from where orbit ended
        let loops: Double = 1.6
        let endRaw = loops * .pi * 2
        let endAngle = endRaw + 0.45 * sin(endRaw) - .pi / 2
        let angle = endAngle + dt * .pi * 3 // fast final spin

        let scale = 1.0 - ease * 0.9
        let opacity = 1.0 - ease * 0.8

        let bx = center.x + cos(angle) * curR
        let by = center.y + sin(angle) * curR
        let r = ballR * scale

        let path = Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2))
        ctx.fill(path, with: .color(.white.opacity(opacity)))
    }

    // MARK: - Drawing Helpers

    private func drawDisc(ctx: GraphicsContext, at center: CGPoint, r: CGFloat, color: Color) {
        let path = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        ctx.fill(path, with: .color(color))
    }

    private func strokeCircle(ctx: GraphicsContext, at center: CGPoint, r: CGFloat, color: Color, width: CGFloat) {
        let path = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        ctx.stroke(path, with: .color(color), lineWidth: width)
    }
}

#if DEBUG
struct GolfBallLoader_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            GolfBallLoader(size: 60)
            GolfBallLoader(size: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}
#endif
