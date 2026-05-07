import SwiftUI
import MeradOSDesign3

/// Apple Design 2026 — Liquid Glass card with optional Apple-Intelligence
/// aurora outline (animated rainbow rim). Use `aurora: true` for cells whose
/// content is AI-generated or actively being computed.
struct AuroraCard<Content: View>: View {
    var radius: CGFloat = MD3.Radii.card
    var padding: CGFloat = 20
    var aurora: Bool = false
    var glass: Bool = true
    @ViewBuilder var content: () -> Content

    @State private var auroraAngle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ContinuousSquircle(cornerRadius: radius)
                    .fill(reduceTransparency ? AnyShapeStyle(MD3.SemColor.surfaceRaised)
                                              : AnyShapeStyle(.thinMaterial))
            }
            .overlay {
                if aurora {
                    auroraOverlay
                }
            }
            .squircleStroke(radius,
                            color: aurora ? Color.clear : MD3.SemColor.divider,
                            lineWidth: 0.5)
            .squircle(radius)
            .shadow(color: .black.opacity(aurora ? 0.18 : 0.08),
                    radius: aurora ? 22 : 10,
                    x: 0,
                    y: aurora ? 8 : 4)
    }

    private var auroraOverlay: some View {
        ContinuousSquircle(cornerRadius: radius)
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear,                                       location: 0.0),
                        .init(color: MD3.SemColor.brandPrimary.opacity(0.65),      location: 0.18),
                        .init(color: MD3.SemColor.brandStrong.opacity(0.85),       location: 0.34),
                        .init(color: MD3.SemColor.brandPrimary.opacity(0.65),      location: 0.50),
                        .init(color: .clear,                                       location: 0.68),
                        .init(color: .clear,                                       location: 1.0),
                    ]),
                    center: .center,
                    angle: .degrees(auroraAngle)
                ),
                lineWidth: 1.6
            )
            .blendMode(.plusLighter)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                    auroraAngle = 360
                }
            }
    }
}

#Preview {
    VStack(spacing: 16) {
        AuroraCard {
            Text("Total NAV")
                .font(MD3.Typo.caption)
                .foregroundStyle(MD3.SemColor.textSecondary)
                .textCase(.uppercase)
            Text("$1,284,902")
                .font(MD3.Typo.title2.monospacedDigit())
                .foregroundStyle(MD3.SemColor.textPrimary)
        }

        AuroraCard(aurora: true) {
            Text("AI Recommendation")
                .font(MD3.Typo.caption)
                .foregroundStyle(MD3.SemColor.textSecondary)
                .textCase(.uppercase)
            Text("12 Caches haven't been touched in 6 months — 2.3 GB reclaimable")
                .font(MD3.Typo.body)
                .foregroundStyle(MD3.SemColor.textPrimary)
        }
    }
    .padding(40)
    .frame(width: 540)
    .preferredColorScheme(.dark)
}
