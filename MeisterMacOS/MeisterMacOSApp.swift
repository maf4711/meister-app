import SwiftUI
import MeradOSDesign3

@main
struct MeisterMacOSApp: App {
    var body: some Scene {
        WindowGroup("Meister") {
            MacRootView()
                .frame(minWidth: 880, minHeight: 600)
                .tint(MD3.SemColor.brandPrimary)
                .background(MD3.SemColor.background)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        Settings {
            MacSettingsView()
                .tint(MD3.SemColor.brandPrimary)
                .preferredColorScheme(.dark)
        }
    }
}
