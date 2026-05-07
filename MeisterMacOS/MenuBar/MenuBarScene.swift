import SwiftUI
import AppKit
import MeradOSDesign3

/// Persistent menu-bar item showing the Meister Health Score.
/// Click to open a popover with quick actions (Quick-Clean, open main window).
struct MenuBarSceneView: View {
    @EnvironmentObject private var nav: NavigationState
    @StateObject private var model = HealthScoreModel()

    private func openModule(_ id: BashModule.ID) {
        nav.selection = id
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Bring main window forward
        for window in NSApplication.shared.windows where window.title == "Meister" {
            window.makeKeyAndOrderFront(nil)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let snap = model.snapshot {
                    HealthRing(progress: Double(snap.score) / 100,
                               size: 60, lineWidth: 6,
                               isComputing: false)
                        .overlay { Text("\(snap.score)").font(.system(size: 20, weight: .light)) }
                } else {
                    ProgressView().frame(width: 60, height: 60)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meister")
                        .font(.headline)
                    Text(model.snapshot.map { _ in scoreVerdict(model.snapshot?.score ?? 0) } ?? "Berechne…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            Button {
                openModule("quick-clean")
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Quick Clean")
                    Spacer()
                }
            }
            .buttonStyle(.borderless)

            Button {
                openModule("dashboard")
            } label: {
                HStack {
                    Image(systemName: "square.grid.2x2.fill")
                    Text("Dashboard öffnen")
                    Spacer()
                }
            }
            .buttonStyle(.borderless)

            Button {
                Task { await model.reload() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Health Score neu")
                    Spacer()
                }
            }
            .buttonStyle(.borderless)

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("Beenden")
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 280)
        .task { await model.reload() }
    }

    private func scoreVerdict(_ s: Int) -> String {
        switch s {
        case 80...:    return "Mac läuft sauber"
        case 50..<80:  return "OK — Optimierungen möglich"
        default:       return "Aufmerksamkeit nötig"
        }
    }
}
