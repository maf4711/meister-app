import SwiftUI
import MeradOSDesign4

/// Apple Design 2026 — ambient mesh-gradient background.
/// Slow drift creates a sense of depth without distraction. Falls back to
/// a static surface when reduce-motion or reduce-transparency is on.
struct MeshBackground: View {
    var intensity: Double = 0.45        // 0...1, how vivid the mesh is
    @State private var t: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                MD4.SemColor.background
            } else if #available(macOS 15.0, iOS 18.0, *) {
                meshLayer
            } else {
                fallbackLayer
            }
        }
        .ignoresSafeArea()
    }

    @available(macOS 15.0, iOS 18.0, *)
    private var meshLayer: some View {
        let drift = reduceMotion ? 0 : t
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5 + 0.05 * sin(drift), 0.0],         [1.0, 0.0],
                [0.0, 0.5 + 0.05 * cos(drift)],
                [0.5 + 0.06 * sin(drift * 0.8),
                 0.5 + 0.06 * cos(drift * 0.8)],
                [1.0, 0.5 - 0.05 * sin(drift)],
                [0.0, 1.0], [0.5 - 0.05 * cos(drift), 1.0],         [1.0, 1.0],
            ].map { SIMD2<Float>(Float($0[0]), Float($0[1])) },
            colors: [
                MD4.SemColor.background,
                MD4.SemColor.surface,
                MD4.SemColor.background,
                MD4.SemColor.brandPrimary.opacity(intensity * 0.30),
                MD4.SemColor.brandStrong.opacity(intensity * 0.18),
                MD4.SemColor.surfaceRaised,
                MD4.SemColor.background,
                MD4.SemColor.surface.opacity(0.9),
                MD4.SemColor.background,
            ]
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: true)) {
                t = .pi * 2
            }
        }
    }

    private var fallbackLayer: some View {
        LinearGradient(
            stops: [
                .init(color: MD4.SemColor.background, location: 0.0),
                .init(color: MD4.SemColor.surface,    location: 0.5),
                .init(color: MD4.SemColor.background, location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

#Preview {
    ZStack {
        MeshBackground(intensity: 0.6)
        Text("Mesh")
            .font(.largeTitle)
            .foregroundStyle(.white)
    }
    .frame(width: 540, height: 360)
    .preferredColorScheme(.dark)
}
