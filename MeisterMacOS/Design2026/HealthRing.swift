import SwiftUI
import MeradOSDesign3

/// Apple Design 2026 — animated health ring.
/// Static state: gradient arc filled to `progress`, color reflects health bucket.
/// Computing state: aurora shimmer on the rim while score is being calculated.
struct HealthRing: View {
    var progress: Double          // 0...1
    var size: CGFloat = 180
    var lineWidth: CGFloat = 14
    var isComputing: Bool = false

    @State private var animatedProgress: Double = 0
    @State private var shimmerAngle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch progress {
        case 0.8...1.0: return MD3.SemColor.success
        case 0.5..<0.8: return MD3.SemColor.warning
        default:        return MD3.SemColor.error
        }
    }

    private var gradientStops: [Gradient.Stop] {
        [
            .init(color: color.opacity(0.55), location: 0.0),
            .init(color: color,                location: 0.6),
            .init(color: color.opacity(0.95), location: 1.0),
        ]
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(MD3.SemColor.surfaceRaised, lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Progress arc with conic gradient
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: gradientStops),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 12, x: 0, y: 0)

            // Aurora shimmer overlay while computing — Apple-Intelligence vibe
            if isComputing {
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear,                                       location: 0.0),
                                .init(color: MD3.SemColor.brandPrimary.opacity(0.65),      location: 0.20),
                                .init(color: MD3.SemColor.brandStrong.opacity(0.85),       location: 0.40),
                                .init(color: MD3.SemColor.brandPrimary.opacity(0.65),      location: 0.55),
                                .init(color: .clear,                                       location: 0.80),
                            ]),
                            center: .center,
                            angle: .degrees(shimmerAngle)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth + 4, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .blendMode(.plusLighter)
                    .opacity(0.7)
            }
        }
        .onAppear {
            if reduceMotion {
                animatedProgress = progress
            } else {
                withAnimation(.timingCurve(0.16, 1.0, 0.30, 1.0, duration: 1.4)) {
                    animatedProgress = progress
                }
            }
            if !reduceMotion && isComputing { startShimmer() }
        }
        .onChange(of: progress) { _, new in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                animatedProgress = new
            }
        }
        .onChange(of: isComputing) { _, computing in
            if computing && !reduceMotion { startShimmer() } else { shimmerAngle = 0 }
        }
    }

    private func startShimmer() {
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
            shimmerAngle = 360
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        HealthRing(progress: 0.85)
        HealthRing(progress: 0.6, isComputing: true)
        HealthRing(progress: 0.32, size: 120, lineWidth: 10)
    }
    .padding(40)
    .preferredColorScheme(.dark)
}
