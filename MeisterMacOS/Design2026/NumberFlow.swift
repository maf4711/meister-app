import SwiftUI
import MeradOSDesign3

/// Animated numeric counter — counts up to its `value` smoothly when first
/// shown, and tweens between values when `value` changes. Tabular numerics
/// so digits don't dance horizontally.
struct NumberFlow: View {
    var value: Double
    var prefix: String = ""
    var suffix: String = ""
    var decimals: Int = 0
    var duration: Double = 1.4
    var font: Font = MD3.Typo.title1

    @State private var displayed: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(value: Double,
         prefix: String = "",
         suffix: String = "",
         decimals: Int = 0,
         duration: Double = 1.4,
         font: Font = MD3.Typo.title1) {
        self.value = value
        self.prefix = prefix
        self.suffix = suffix
        self.decimals = decimals
        self.duration = duration
        self.font = font
    }

    /// Convenience for Int values.
    init(_ value: Int,
         prefix: String = "",
         suffix: String = "",
         font: Font = MD3.Typo.title1) {
        self.init(value: Double(value),
                  prefix: prefix,
                  suffix: suffix,
                  decimals: 0,
                  duration: 1.0,
                  font: font)
    }

    var body: some View {
        Text(format(displayed))
            .font(font.monospacedDigit())
            .contentTransition(.numericText())
            .onAppear {
                if reduceMotion {
                    displayed = value
                } else {
                    withAnimation(.timingCurve(0.16, 1.0, 0.30, 1.0, duration: duration)) {
                        displayed = value
                    }
                }
            }
            .onChange(of: value) { _, newValue in
                if reduceMotion {
                    displayed = newValue
                } else {
                    withAnimation(.snappy(duration: 0.5)) {
                        displayed = newValue
                    }
                }
            }
    }

    private func format(_ v: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        formatter.usesGroupingSeparator = true
        formatter.numberStyle = .decimal
        let core = formatter.string(from: NSNumber(value: v)) ?? "0"
        return "\(prefix)\(core)\(suffix)"
    }
}

#Preview {
    VStack(spacing: 16) {
        NumberFlow(value: 1_284_902, prefix: "$")
        NumberFlow(value: 4.82, prefix: "$", decimals: 2, font: MD3.Typo.title2)
        NumberFlow(85, suffix: "/100")
    }
    .padding(40)
    .preferredColorScheme(.dark)
}
