import SwiftUI
import MeradOSDesign2

@main
struct MeisterIOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color.meradBrandPrimary)
                .meradDarkMode()
                .background(Color.meradBg.ignoresSafeArea())
        }
    }
}
