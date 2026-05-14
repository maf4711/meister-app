import SwiftUI
import MeradOSDesign4

@main
struct MeisterIOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(MD4.SemColor.brandPrimary)
                .preferredColorScheme(.dark)
                .background(MD4.SemColor.background.ignoresSafeArea())
        }
    }
}
