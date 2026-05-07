import SwiftUI
import MeradOSDesign3

/// Apple Design 2026 — celebration particles after a successful action.
/// Use as `.sparkleBurst(trigger:)` on a view; it draws a one-shot particle
/// emission centered on the view whenever `trigger` flips to true.
struct SparkleBurst: View {
    let trigger: Bool
    var color: Color = MD3.SemColor.brandPrimary
    var particleCount: Int = 24

    @State private var particles: [Particle] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Particle: Identifiable {
        let id = UUID()
        var dx: CGFloat
        var dy: CGFloat
        var rotation: Double
        var scale: CGFloat
        var opacity: Double
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { p in
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(color)
                        .scaleEffect(p.scale)
                        .opacity(p.opacity)
                        .rotationEffect(.degrees(p.rotation))
                        .offset(x: p.dx, y: p.dy)
                        .blendMode(.plusLighter)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .allowsHitTesting(false)
        }
        .onChange(of: trigger) { _, new in
            guard new, !reduceMotion else { return }
            burst()
        }
    }

    private func burst() {
        var seeds: [Particle] = []
        for _ in 0..<particleCount {
            seeds.append(Particle(dx: 0, dy: 0,
                                  rotation: Double.random(in: -180...180),
                                  scale: 0.2,
                                  opacity: 1))
        }
        particles = seeds

        // Animate outward + fade.
        for index in seeds.indices {
            let angle = Double.random(in: 0..<(2 * .pi))
            let distance = CGFloat.random(in: 60...160)
            let dx = CGFloat(cos(angle)) * distance
            let dy = CGFloat(sin(angle)) * distance
            let scale = CGFloat.random(in: 0.7...1.3)

            withAnimation(.timingCurve(0.16, 1.0, 0.30, 1.0, duration: 0.9)
                            .delay(Double.random(in: 0...0.05))) {
                particles[index].dx = dx
                particles[index].dy = dy
                particles[index].scale = scale
                particles[index].rotation += Double.random(in: 90...360)
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.4)) {
                particles[index].opacity = 0
            }
        }
        // Cleanup after the longest delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            particles.removeAll()
        }
    }
}

extension View {
    /// Layer a sparkle burst on top of any view; triggered when `trigger` flips.
    func sparkleBurst(trigger: Bool, color: Color = MD3.SemColor.brandPrimary) -> some View {
        overlay(SparkleBurst(trigger: trigger, color: color).allowsHitTesting(false))
    }
}

#Preview {
    struct Demo: View {
        @State private var fire = false
        var body: some View {
            ZStack {
                Color.black
                Button("Burst") { fire.toggle() }
                    .buttonStyle(.borderedProminent)
                    .sparkleBurst(trigger: fire)
            }
            .frame(width: 360, height: 240)
        }
    }
    return Demo()
}
