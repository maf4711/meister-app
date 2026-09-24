import SwiftUI
import AppKit
import MeradOSDesign4

/// Apple Design 2026 — the new top-of-app Dashboard.
/// Bento grid: Health Ring (2-tile span), reclaimable storage (1×1),
/// security status (1×1), recent activity (2×1), AI recommendation (2×1
/// with aurora outline).
struct DashboardView: View {
    @StateObject private var model = DashboardModel()
    @EnvironmentObject private var nav: NavigationState

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
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text(greeting)
                    .font(MD4.Typo.body)
                    .foregroundStyle(MD4.SemColor.textSecondary)
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
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 16) {
                healthRingTile
                reclaimableTile
                securityTile
                snapshotsTile
            }
            aiRecommendationTile
        }
    }

    // MARK: tiles

    private var healthRingTile: some View {
        AuroraCard(radius: MD4.Radii.lg, padding: 24, aurora: model.isLoading) {
            VStack(spacing: 12) {
                HStack {
                    Text("Health Score")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
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
                                .foregroundStyle(MD4.SemColor.textPrimary)
                            Text("/ 100")
                                .font(MD4.Typo.caption)
                                .foregroundStyle(MD4.SemColor.textSecondary)
                        }
                    }
                if let snap = model.snapshot {
                    Text(!snap.hasMeasurements ? "Keine Messwerte" : snap.hasUnknowns ? "Teilbewertung — Messwerte fehlen" : verdict(snap.score))
                        .font(MD4.Typo.small)
                        .foregroundStyle(verdictColor(snap.score))
                        .padding(.top, 4)
                }
            }
        }
    }

    private var reclaimableTile: some View {
        AuroraCard(radius: MD4.Radii.lg, padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(MD4.SemColor.brandPrimary)
                    Text("Zur Prüfung")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                }
                NumberFlow(value: Double(model.reclaimableBytes) / 1_073_741_824,
                           suffix: " GB",
                           decimals: 1,
                           font: .system(size: 42, weight: .light))
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Geschätzte Dateigröße; Freigabe erst nach Prüfung.")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
        }
    }

    private var securityTile: some View {
        AuroraCard(radius: MD4.Radii.lg, padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: model.allSecurityOK
                          ? "checkmark.shield.fill"
                          : "exclamationmark.shield.fill")
                        .foregroundStyle(model.allSecurityOK
                                         ? MD4.SemColor.success
                                         : MD4.SemColor.warning)
                    Text("Security")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                }
                Text(model.allSecurityOK ? "Alles aktiv" : "\(model.securityIssueCount) Hinweis\(model.securityIssueCount == 1 ? "" : "e")")
                    .font(MD4.Typo.title3)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("FileVault · Firewall · Gatekeeper · SIP")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
        }
    }

    private var snapshotsTile: some View {
        AuroraCard(radius: MD4.Radii.lg, padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(MD4.SemColor.brandPrimary)
                    Text("Backup")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                }
                if let last = model.lastBackup {
                    Text(last.formatted(.relative(presentation: .named)))
                        .font(MD4.Typo.title3)
                        .foregroundStyle(MD4.SemColor.textPrimary)
                } else {
                    Text("Keine Zeitangabe")
                        .font(MD4.Typo.title3)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
                Text("\(model.snapshotCount) APFS-Snapshots")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
        }
    }

    private var aiRecommendationTile: some View {
        AuroraCard(radius: MD4.Radii.lg, padding: 24, aurora: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(MD4.SemColor.brandPrimary)
                    Text("Nächste Schritte")
                        .font(MD4.Typo.caption.bold())
                        .foregroundStyle(MD4.SemColor.brandPrimary)
                        .textCase(.uppercase)
                    Spacer()
                }
                if model.isLoading {
                    ProgressView("Diagnose läuft…")
                } else if model.snapshot == nil {
                    Text("Diagnose noch nicht verfügbar.")
                } else if model.recommendations.isEmpty {
                    Text(model.snapshot?.hasUnknowns == true ? "Diagnose unvollständig" : "Keine dringenden Maßnahmen erkannt")
                        .font(MD4.Typo.title3)
                    Text("Bewertung aus lokalen Messwerten. Bereinigungen bleiben deine Entscheidung.")
                        .font(MD4.Typo.small)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                } else {
                    ForEach(model.recommendations) { recommendation in
                        Button { nav.selection = recommendation.moduleID } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recommendation.title).font(MD4.Typo.headline)
                                    Text(recommendation.detail).font(MD4.Typo.small)
                                        .foregroundStyle(MD4.SemColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.padding(.vertical, 8)
                        }.buttonStyle(.plain)
                    }
                }
                if let timestamp = model.snapshot?.timestamp {
                    Text("Stand: \(timestamp.formatted(date: .abbreviated, time: .shortened))")
                        .font(MD4.Typo.caption).foregroundStyle(MD4.SemColor.textSecondary)
                }

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
        case 80...:   return MD4.SemColor.success
        case 50..<80: return MD4.SemColor.warning
        default:      return MD4.SemColor.error
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(NavigationState())
        .frame(width: 900, height: 720)
        .preferredColorScheme(.dark)
}
