import SwiftUI
import MeradOSDesign3

@main
struct MeisterMacOSApp: App {
    /// Selection bus for deep-link URLs and menu-bar quick-actions.
    @StateObject private var nav = NavigationState()

    @AppStorage("meister.onboarding.completed.v1") private var hasSeenOnboarding: Bool = false
    @State private var showOnboarding: Bool = false

    var body: some Scene {
        WindowGroup("Meister") {
            MacRootView()
                .environmentObject(nav)
                .frame(minWidth: 880, minHeight: 600)
                .tint(MD3.SemColor.brandPrimary)
                .background(MD3.SemColor.background)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handleURL(url)
                }
                .overlay {
                    if showOnboarding {
                        OnboardingView(isPresented: $showOnboarding)
                            .environmentObject(nav)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .animation(.snappy, value: showOnboarding)
                .onAppear {
                    if !hasSeenOnboarding { showOnboarding = true }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        Settings {
            MacSettingsView()
                .tint(MD3.SemColor.brandPrimary)
                .preferredColorScheme(.dark)
        }

        MenuBarExtra("Meister", systemImage: "heart.text.square.fill") {
            MenuBarSceneView()
                .environmentObject(nav)
        }
        .menuBarExtraStyle(.window)
    }

    /// `meister://run/<module-id>` — Apple Shortcuts + menu-bar buttons.
    private func handleURL(_ url: URL) {
        guard url.scheme == "meister", url.host == "run" else { return }
        let target = url.lastPathComponent
        if BashModule.all.contains(where: { $0.id == target }) {
            nav.selection = target
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
