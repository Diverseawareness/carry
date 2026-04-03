import SwiftUI

struct SkinConfettiBurst: View {
    let playerColor: Color
    let onComplete: () -> Void

    @State private var startTime: Date?

    private static let duration: Double = 1.1
    private let particles: [ConfettiParticle]

    init(playerColor: Color, onComplete: @escaping () -> Void) {
        self.playerColor = playerColor
        self.onComplete = onComplete
        self.particles = Self.generateParticles(playerColor: playerColor)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = startTime.map { timeline.date.timeIntervalSince($0) } ?? 0
            let progress = min(elapsed / Self.duration, 1.0)

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for particle in particles {
                    let pos = particle.position(at: progress, center: center)
                    let opacity = particle.opacity(at: progress)
                    let scale = particle.scale(at: progress)

                    guard opacity > 0.01 else { continue }

                    var ctx = context
                    ctx.opacity = opacity

                    let s = particle.size * scale
                    let rect = CGRect(x: pos.x - s / 2, y: pos.y - s / 2, width: s, height: s)

                    if particle.isCircle {
                        ctx.fill(Circle().path(in: rect), with: .color(particle.color))
                    } else {
                        let rotation = Angle.degrees(particle.rotationSpeed * progress * 360)
                        ctx.translateBy(x: pos.x, y: pos.y)
                        ctx.rotate(by: rotation)
                        let r = CGRect(x: -s / 2, y: -s * 0.3 / 2, width: s, height: s * 0.3)
                        ctx.fill(Rectangle().path(in: r), with: .color(particle.color))
                        ctx.rotate(by: -rotation)
                        ctx.translateBy(x: -pos.x, y: -pos.y)
                    }
                }
            }
            .onChange(of: progress >= 1.0) { _, done in
                if done { onComplete() }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            startTime = Date()
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    // MARK: - Particle Generation

    private static let goldColors: [Color] = [
        Color.gold,
        Color(hexString: "#F5D780"),
        Color.goldMuted,
        Color.goldStandard,
        .white
    ]

    private static func generateParticles(playerColor: Color) -> [ConfettiParticle] {
        var particles: [ConfettiParticle] = []
        let palette = goldColors + [playerColor, playerColor]

        for _ in 0..<40 {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 20...60)
            let size = CGFloat.random(in: 3...8)
            let color = palette.randomElement() ?? .white
            let isCircle = Bool.random()
            let rotationSpeed = Double.random(in: 0.5...2.5)

            particles.append(ConfettiParticle(
                angle: angle,
                speed: speed,
                size: size,
                color: color,
                isCircle: isCircle,
                rotationSpeed: rotationSpeed
            ))
        }
        return particles
    }
}

// MARK: - Particle Model

private struct ConfettiParticle {
    let angle: Double
    let speed: Double
    let size: CGFloat
    let color: Color
    let isCircle: Bool
    let rotationSpeed: Double

    func position(at progress: Double, center: CGPoint) -> CGPoint {
        let eased = 1 - pow(1 - progress, 2) // ease-out
        let dist = speed * eased
        return CGPoint(
            x: center.x + cos(angle) * dist,
            y: center.y + sin(angle) * dist
        )
    }

    func opacity(at progress: Double) -> Double {
        progress < 0.35 ? 1.0 : max(0, 1 - (progress - 0.35) / 0.65)
    }

    func scale(at progress: Double) -> Double {
        1.0 - progress * 0.5
    }
}
