import SwiftUI

@main
struct MeisterMacOSApp: App {
    var body: some Scene {
        WindowGroup("Meister") {
            MacRootView()
                .frame(minWidth: 880, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        Settings {
            MacSettingsView()
        }
    }
}
