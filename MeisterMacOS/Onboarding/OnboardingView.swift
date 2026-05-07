import SwiftUI
import MeradOSDesign3

@MainActor
final class OnboardingState: ObservableObject {
    @AppStorage("meister.onboarding.completed.v1") var hasSeen: Bool = false
    @Published var currentPage: Int = 0
}

struct OnboardingView: View {
    @StateObject private var state = OnboardingState()
    @EnvironmentObject private var nav: NavigationState
    @Binding var isPresented: Bool

    private let pages: [OnboardingPage] = [
        .init(icon: "wand.and.stars",
              title: "Quick Clean",
              subtitle: "Ein Klick, alle Caches in den Trash",
              body: "Caches, Logs, Browser-Müll, Xcode-DerivedData, npm/pip/Homebrew. Reversibel — alles geht in ~/.Trash, mit Undo Last Cleanup zurückholbar."),
        .init(icon: "shield.lefthalf.filled",
              title: "Security & Audit",
              subtitle: "Mac-Sicherheit auf einen Blick",
              body: "FileVault, Firewall, Gatekeeper, SIP, Keychain-Items, SSH-Keys, App-Permissions. Read-only — alles diagnostisch."),
        .init(icon: "wand.and.rays",
              title: "Smart Recommendations",
              subtitle: "Health-Score, Forecast, Autopilot",
              body: "0–100-Score aus Sicherheit + Backup + Cleanup-Druck. Forecast wann die Disk voll ist. Autopilot räumt täglich um 03:30 auf."),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 0) {
                content
                Divider().background(MD3.SemColor.divider)
                footer
            }
            .frame(width: 540, height: 460)
            .background(.thinMaterial)
            .squircle(MD3.Radii.lg)
            .squircleStroke(MD3.Radii.lg, color: MD3.SemColor.divider, lineWidth: 0.5)
            .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        }
    }

    private var content: some View {
        TabView(selection: $state.currentPage) {
            ForEach(Array(pages.enumerated()), id: \.offset) { idx, page in
                pageView(page).tag(idx)
            }
        }
        .tabViewStyle(.automatic)
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 20)
            Image(systemName: page.icon)
                .font(.system(size: 56))
                .foregroundStyle(MD3.SemColor.brandPrimary)
                .padding(.bottom, 4)
            Text(page.title)
                .font(MD3.Typo.title1)
                .foregroundStyle(MD3.SemColor.textPrimary)
            Text(page.subtitle)
                .font(MD3.Typo.headline)
                .foregroundStyle(MD3.SemColor.textSecondary)
            Text(page.body)
                .font(MD3.Typo.body)
                .foregroundStyle(MD3.SemColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Button(state.currentPage > 0 ? "Zurück" : "Skip") {
                if state.currentPage > 0 {
                    state.currentPage -= 1
                } else {
                    finish()
                }
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Circle()
                        .fill(i == state.currentPage ? MD3.SemColor.brandPrimary : MD3.SemColor.surfaceRaised)
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if state.currentPage < pages.count - 1 {
                Button("Weiter") {
                    state.currentPage += 1
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Loslegen") {
                    finish()
                    nav.selection = "dashboard"
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func finish() {
        state.hasSeen = true
        isPresented = false
    }
}

private struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let body: String
}
