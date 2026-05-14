import SwiftUI
import MeradOSDesign4

/// Apple Design 2026 — Liquid Glass card with optional Apple-Intelligence
/// aurora outline (animated rainbow rim). Use `aurora: true` for cells whose
/// content is AI-generated or actively being computed.
struct AuroraCard<Content: View>: View {
    var radius: CGFloat = MD4.Radii.card
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
                    .fill(reduceTransparency ? AnyShapeStyle(MD4.SemColor.surfaceRaised)
                                              : AnyShapeStyle(.thinMaterial))
            }
            .overlay {
                if aurora {
                    auroraOverlay
                }
            }
            .squircleStroke(radius,
                            color: aurora ? Color.clear : MD4.SemColor.divider,
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
                        .init(color: MD4.SemColor.brandPrimary.opacity(0.65),      location: 0.18),
                        .init(color: MD4.SemColor.brandStrong.opacity(0.85),       location: 0.34),
                        .init(color: MD4.SemColor.brandPrimary.opacity(0.65),      location: 0.50),
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
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
                .textCase(.uppercase)
            Text("$1,284,902")
                .font(MD4.Typo.title2.monospacedDigit())
                .foregroundStyle(MD4.SemColor.textPrimary)
        }

        AuroraCard(aurora: true) {
            Text("AI Recommendation")
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
                .textCase(.uppercase)
            Text("12 Caches haven't been touched in 6 months — 2.3 GB reclaimable")
                .font(MD4.Typo.body)
                .foregroundStyle(MD4.SemColor.textPrimary)
        }
    }
    .padding(40)
    .frame(width: 540)
    .preferredColorScheme(.dark)
}
