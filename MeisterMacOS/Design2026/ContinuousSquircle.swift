import SwiftUI

/// Apple Design 2026 — continuous-corner squircle.
/// Uses RoundedRectangle with `.continuous` style, which on macOS 14+ /
/// iOS 17+ produces the proper iPhone-button-shaped curve (G2 continuity).
struct ContinuousSquircle: InsettableShape {
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: inset)
    }

    func inset(by amount: CGFloat) -> ContinuousSquircle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

extension View {
    /// Clip to a continuous-corner squircle.
    func squircle(_ radius: CGFloat) -> some View {
        clipShape(ContinuousSquircle(cornerRadius: radius))
    }

    /// Round to squircle and stroke its border in one call.
    func squircleStroke(_ radius: CGFloat,
                       color: Color,
                       lineWidth: CGFloat = 1) -> some View {
        overlay(
            ContinuousSquircle(cornerRadius: radius)
                .stroke(color, lineWidth: lineWidth)
        )
    }
}

/// Concentric children — a child squircle inside a padded parent shares
/// the same curve center, which is the iOS 26 / Tahoe continuity rule.
extension ContinuousSquircle {
    static func concentric(parent: CGFloat, padding: CGFloat) -> CGFloat {
        max(0, parent - padding)
    }
}
