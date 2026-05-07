import SwiftUI
import MeradOSDesign3

@main
struct MeisterIOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(MD3.SemColor.brandPrimary)
                .preferredColorScheme(.dark)
                .background(MD3.SemColor.background.ignoresSafeArea())
        }
    }
}
