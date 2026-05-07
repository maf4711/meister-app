import SwiftUI
import AppKit
import MeradOSDesign3

/// Apple Design 2026 — the new top-of-app Dashboard.
/// Bento grid: Health Ring (2-tile span), reclaimable storage (1×1),
/// security status (1×1), recent activity (2×1), AI recommendation (2×1
/// with aurora outline).
struct DashboardView: View {
    @StateObject private var model = DashboardModel()
    @State private var celebrate = false

    var body: some View {
        ZStack {
            MeshBackground(intensity: 0.55)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    bento
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { if model.snapshot == nil { await model.reload() } }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meister")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text(greeting)
                    .font(MD3.Typo.body)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11:  return "Morgen — alles im Lot?"
        case 11..<14: return "Mittag — Mac läuft sauber?"
        case 14..<18: return "Nachmittag — Zeit für ein Cleanup?"
        case 18..<22: return "Abend — letzter Health-Check?"
        default:      return "Spätschicht — wie hält der Mac sich?"
        }
    }

    // MARK: bento grid

    @ViewBuilder
    private var bento: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()),
                    GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: cols, spacing: 16) {
            // Health Ring — 2x2
            healthRingTile
                .gridCellColumns(2)
            // Reclaimable Storage — 2x1
            reclaimableTile
                .gridCellColumns(2)
            // Security badge — 2x1
            securityTile
                .gridCellColumns(2)
            // Snapshots count — 2x1
            snapshotsTile
                .gridCellColumns(2)
            // AI Recommendation — 4-wide
            aiRecommendationTile
                .gridCellColumns(4)
        }
    }

    // MARK: tiles

    private var healthRingTile: some View {
        AuroraCard(radius: MD3.Radii.lg, padding: 24, aurora: model.isLoading) {
            VStack(spacing: 12) {
                HStack {
                    Text("Health Score")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                }
                HealthRing(progress: Double(model.snapshot?.score ?? 0) / 100,
                           size: 180,
                           lineWidth: 14,
                           isComputing: model.isLoading)
                    .overlay {
                        VStack(spacing: 0) {
                            NumberFlow(model.snapshot?.score ?? 0,
                                       font: .system(size: 56, weight: .light, design: .default))
                                .foregroundStyle(MD3.SemColor.textPrimary)
                            Text("/ 100")
                                .font(MD3.Typo.caption)
                                .foregroundStyle(MD3.SemColor.textSecondary)
                        }
                    }
                if let snap = model.snapshot {
                    Text(verdict(snap.score))
                        .font(MD3.Typo.small)
                        .foregroundStyle(verdictColor(snap.score))
                        .padding(.top, 4)
                }
            }
        }
    }

    private var reclaimableTile: some View {
        AuroraCard(radius: MD3.Radii.lg, padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(MD3.SemColor.brandPrimary)
                    Text("Reclaimable")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                }
                NumberFlow(value: Double(model.reclaimableBytes) / 1_073_741_824,
                           suffix: " GB",
                           decimals: 1,
                           font: .system(size: 42, weight: .light))
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("System Cleanup, Caches, Logs, Trash")
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
        }
    }

    private var securityTile: some View {
        AuroraCard(radius: MD3.Radii.lg, padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: model.allSecurityOK
                          ? "checkmark.shield.fill"
                          : "exclamationmark.shield.fill")
                        .foregroundStyle(model.allSecurityOK
                                         ? MD3.SemColor.success
                                         : MD3.SemColor.warning)
                    Text("Security")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                }
                Text(model.allSecurityOK ? "Alles aktiv" : "\(model.securityIssueCount) Hinweis\(model.securityIssueCount == 1 ? "" : "e")")
                    .font(MD3.Typo.title3)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("FileVault · Firewall · Gatekeeper · SIP")
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
        }
    }

    private var snapshotsTile: some View {
        AuroraCard(radius: MD3.Radii.lg, padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(MD3.SemColor.brandPrimary)
                    Text("Backup")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                }
                if let last = model.lastBackup {
                    Text(last.formatted(.relative(presentation: .named)))
                        .font(MD3.Typo.title3)
                        .foregroundStyle(MD3.SemColor.textPrimary)
                } else {
                    Text("kein Backup")
                        .font(MD3.Typo.title3)
                        .foregroundStyle(MD3.SemColor.warning)
                }
                Text("\(model.snapshotCount) APFS-Snapshots")
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
        }
    }

    private var aiRecommendationTile: some View {
        AuroraCard(radius: MD3.Radii.lg, padding: 24, aurora: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(MD3.SemColor.brandPrimary)
                    Text("Smart Recommendation")
                        .font(MD3.Typo.caption.bold())
                        .foregroundStyle(MD3.SemColor.brandPrimary)
                        .textCase(.uppercase)
                    Spacer()
                }
                Text(model.recommendation)
                    .font(MD3.Typo.title3)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text(model.recommendationDetail)
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
        }
    }

    private func verdict(_ score: Int) -> String {
        switch score {
        case 90...:    return "Mac läuft erstklassig"
        case 75..<90:  return "Sehr gut — kleine Optimierungen möglich"
        case 50..<75:  return "OK, aber etwas hat sich angesammelt"
        default:       return "Mehrere Aufmerksamkeitspunkte"
        }
    }

    private func verdictColor(_ score: Int) -> Color {
        switch score {
        case 80...:   return MD3.SemColor.success
        case 50..<80: return MD3.SemColor.warning
        default:      return MD3.SemColor.error
        }
    }
}

#Preview {
    DashboardView()
        .frame(width: 900, height: 720)
        .preferredColorScheme(.dark)
}
