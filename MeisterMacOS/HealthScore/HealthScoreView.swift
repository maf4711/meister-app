import SwiftUI
import MeradOSDesign3

@MainActor
final class HealthScoreModel: ObservableObject {
    @Published var snapshot: HealthSnapshot?
    @Published var isLoading = false
    private let reader = HealthScoreReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.snapshot = await reader.snapshot()
    }
}

struct HealthScoreView: View {
    @StateObject private var model = HealthScoreModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
        .task { if model.snapshot == nil { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Health Score")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("Eine Zahl 0-100. Sicherheit, Backup, Cleanup-Druck, Snapshots zusammengezählt.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Neu berechnen", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if let snap = model.snapshot {
            VStack(spacing: 16) {
                scoreCircle(snap.score)
                    .padding(.top, 16)
                signals(snap.signals)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func scoreCircle(_ score: Int) -> some View {
        HealthRing(progress: Double(score) / 100,
                   size: 180,
                   lineWidth: 14,
                   isComputing: model.isLoading)
            .overlay {
                VStack(spacing: 0) {
                    NumberFlow(score, font: .system(size: 56, weight: .light))
                        .foregroundStyle(MD3.SemColor.textPrimary)
                    Text("/ 100")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                }
            }
    }

    private func signals(_ signals: [HealthSignal]) -> some View {
        List {
            ForEach(signals) { sig in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sig.title)
                            .font(MD3.Typo.body)
                            .foregroundStyle(MD3.SemColor.textPrimary)
                        Text(sig.detail)
                            .font(MD3.Typo.caption)
                            .foregroundStyle(MD3.SemColor.textSecondary)
                    }
                    Spacer()
                    Text("\(sig.earned)/\(sig.weight)")
                        .font(MD3.Typo.tabular(MD3.Typo.body))
                        .foregroundStyle(sig.earned == sig.weight
                                         ? MD3.SemColor.success
                                         : MD3.SemColor.warning)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    HealthScoreView()
        .frame(width: 720, height: 600)
        .preferredColorScheme(.dark)
}
