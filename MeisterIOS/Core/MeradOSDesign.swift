// meradOS Design System — SwiftUI Tokens
// Import in any Apple platform project

import SwiftUI

// MARK: - Brand Colors

extension Color {
    struct MeradOS {
        // Brand palette
        static let brand50  = Color(red: 0.94, green: 0.98, blue: 1.0)
        static let brand100 = Color(red: 0.88, green: 0.95, blue: 1.0)
        static let brand200 = Color(red: 0.73, green: 0.90, blue: 0.99)
        static let brand300 = Color(red: 0.49, green: 0.83, blue: 0.99)  // needle accent
        static let brand400 = Color(red: 0.22, green: 0.74, blue: 0.97)  // primary
        static let brand500 = Color(red: 0.05, green: 0.65, blue: 0.91)  // subtle
        static let brand600 = Color(red: 0.01, green: 0.52, blue: 0.78)
        static let brand700 = Color(red: 0.01, green: 0.41, blue: 0.63)
        static let brand800 = Color(red: 0.03, green: 0.35, blue: 0.52)
        static let brand900 = Color(red: 0.05, green: 0.29, blue: 0.43)  // south needle

        // Backgrounds
        static let bg       = Color(red: 0.02, green: 0.02, blue: 0.03)
        static let surface  = Color(red: 0.04, green: 0.04, blue: 0.06)

        // Semantic
        static let success = Color(red: 0.20, green: 0.83, blue: 0.60)
        static let warning = Color(red: 0.96, green: 0.65, blue: 0.14)
        static let error   = Color(red: 0.94, green: 0.27, blue: 0.27)
        static let info    = Color(red: 0.23, green: 0.51, blue: 0.96)
    }
}

// MARK: - Text Colors

extension ShapeStyle where Self == Color {
    static var meradPrimary:   Color { .white.opacity(0.88) }
    static var meradSecondary: Color { .white.opacity(0.45) }
    static var meradTertiary:  Color { .white.opacity(0.20) }
}

// MARK: - Typography

extension Font {
    struct MeradOS {
        // Logo — matches macOS wordmark style
        static func logo(size: CGFloat = 42) -> Font {
            .system(size: size, weight: .ultraLight, design: .default)
        }

        // Tagline
        static var tagline: Font {
            .system(size: 9, weight: .regular, design: .default)
        }
    }
}

// MARK: - Spacing

enum MeradSpacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 16
    static let lg:  CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radius (iOS 26 continuous / squircle)
//
// Every rounded shape uses `.continuous`. The concentric rule: nested
// shape radius = outer radius − padding. Call `MeradRadius.concentric`
// so you never have to do the math twice.

enum MeradRadius {
    static let xs:         CGFloat = 6
    static let small:      CGFloat = 10
    static let medium:     CGFloat = 14
    static let large:      CGFloat = 20      // iOS 26 default card
    static let extraLarge: CGFloat = 26
    static let xxl:        CGFloat = 32      // sheets, full-screen modals

    static let card:       CGFloat = 20
    static let cardInner:  CGFloat = 14
    static let sheet:      CGFloat = 32
    static let popover:    CGFloat = 18
    static let tabBar:     CGFloat = 28      // floating capsule
    static let toolbar:    CGFloat = 24
    static let control:    CGFloat = 14

    #if os(macOS)
    static let window: CGFloat = 12          // macOS 26 Tahoe raised
    #elseif os(tvOS)
    static let window: CGFloat = 28
    #elseif os(visionOS)
    static let window: CGFloat = 32
    #else
    static let window: CGFloat = 20
    #endif

    /// Concentric helper — child radius inside a padded parent.
    static func concentric(outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(0, outer - padding)
    }

    /// Shape used in every rounded container. Shortcut for readability.
    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

// MARK: - iOS 26 Liquid Glass Materials
//
// Apply to nav bars, tab bars, popovers, sheets. Use `.glass(.thin)` as the
// one call-site. Respect `accessibilityReduceTransparency` automatically.

enum MeradMaterial {
    case thin   // all chrome: nav bars, tab bars, toolbars, popovers
    case thick  // sheets and full-screen modals

    var material: Material {
        switch self {
        case .thin:  return .thinMaterial
        case .thick: return .thickMaterial
        }
    }
}

extension View {
    /// iOS 26 glass surface — chrome for nav/tab/toolbar/sheet.
    /// Auto-falls back to opaque surface when Reduce Transparency is on.
    func glass(_ material: MeradMaterial = .thin,
               cornerRadius: CGFloat = MeradRadius.tabBar) -> some View {
        modifier(GlassModifier(material: material, cornerRadius: cornerRadius))
    }
}

private struct GlassModifier: ViewModifier {
    let material: MeradMaterial
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(
                Group {
                    if reduceTransparency {
                        Color.MeradAdaptive.surface
                    } else {
                        shape.fill(material.material)
                    }
                }
            )
            .overlay(
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(shape)
    }
}

// MARK: - iOS 26 Control Sizes (iOS, iPadOS, macOS, tvOS)

enum MeradControlSize {
    #if os(iOS) || os(visionOS)
    static let mini:   CGFloat = 20
    static let small:  CGFloat = 28
    static let medium: CGFloat = 34
    static let large:  CGFloat = 50
    #elseif os(macOS)
    static let mini:   CGFloat = 16
    static let small:  CGFloat = 20
    static let medium: CGFloat = 24
    static let large:  CGFloat = 28
    #elseif os(tvOS)
    static let small:  CGFloat = 40
    static let medium: CGFloat = 54
    static let large:  CGFloat = 72
    #elseif os(watchOS)
    static let small:  CGFloat = 28
    static let medium: CGFloat = 34
    static let large:  CGFloat = 40
    #endif
}

// MARK: - Dynamic Type Helpers
//
// Always prefer SwiftUI's built-in `.font(.body)` etc. so Dynamic Type
// scales automatically. Use the rounded variant for pills and tab labels.

extension Font {
    static var meradRoundedBody: Font   { .system(.body, design: .rounded) }
    static var meradRoundedTitle: Font  { .system(.title3, design: .rounded, weight: .semibold) }
    static var meradNumeric: Font       { .system(.body, design: .default).monospacedDigit() }
}

// MARK: - Compass Rose View

struct CompassRoseView: View {
    var size: CGFloat = 80

    var body: some View {
        Image("compass-rose", bundle: .main)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

// MARK: - Logo View

struct MeradOSLogo: View {
    var roseSize: CGFloat = 100
    var fontSize: CGFloat = 42
    var showTagline: Bool = true

    var body: some View {
        VStack(spacing: MeradSpacing.md) {
            CompassRoseView(size: roseSize)

            Text("meradOS")
                .font(.MeradOS.logo(size: fontSize))
                .foregroundStyle(.meradPrimary)
                .tracking(fontSize * 0.02)

            if showTagline {
                Text("GPS FOR MONEY")
                    .font(.MeradOS.tagline)
                    .foregroundStyle(Color.MeradOS.brand500.opacity(0.4))
                    .tracking(4.5)
            }
        }
    }
}

// MARK: - Adaptive Colors (dark-mode-only design system)
//
// meradOS is dark-only by design. These accessors always return the dark
// palette. The `light:dark:` initializer is kept as a no-op shim for any
// legacy call sites — both arguments resolve to `dark`.

extension Color {
    struct MeradAdaptive {
        static var background:    Color { .MeradOS.bg }
        static var surface:       Color { .MeradOS.surface }
        static var textPrimary:   Color { .white.opacity(0.88) }
        static var textSecondary: Color { .white.opacity(0.45) }
        static var textTertiary:  Color { .white.opacity(0.25) }
        static var border:        Color { .white.opacity(0.04) }
    }
}

extension Color {
    /// Legacy shim — always returns `dark`. meradOS is dark-mode only.
    init(light _: Color, dark: Color) {
        self = dark
    }
}

// MARK: - Dark-Mode Enforcement
//
// Apply at the root of every scene so meradOS ignores the system setting.
// iOS / iPadOS / tvOS / visionOS: call `.meradDarkMode()` on your root view.
// macOS 26 Tahoe: call `.meradDarkMode()` *and* set
//   `NSApp.appearance = NSAppearance(named: .darkAqua)` at launch.
// For stricter guarantee set `UIUserInterfaceStyle = Dark` in Info.plist.

extension View {
    /// Locks this view tree (and all children) to dark mode.
    func meradDarkMode() -> some View {
        self
            .preferredColorScheme(.dark)
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Preview

#Preview("meradOS Logo") {
    ZStack {
        Color.MeradOS.bg.ignoresSafeArea()
        MeradOSLogo()
    }
}
