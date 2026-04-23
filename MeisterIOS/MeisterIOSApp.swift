import SwiftUI

@main
struct MeisterIOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color.MeradOS.brand400)
                .meradDarkMode()
                .background(Color.MeradOS.bg.ignoresSafeArea())
        }
    }
}
