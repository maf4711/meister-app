import SwiftUI

/// User-selectable appearance: defaults to `system` so the app follows iOS settings
/// (light during day / dark at night / manual override). Persisted in UserDefaults.
enum ThemePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension View {
    /// Applies the stored theme preference. `nil` color scheme means "follow system".
    func meisterTheme(_ preference: ThemePreference) -> some View {
        preferredColorScheme(preference.colorScheme)
    }
}
