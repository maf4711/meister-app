import SwiftUI
import MeradOSDesign4

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

    /// Auto-refresh loop for `.task`. Cancels with view disappear.
    func startAutoRefresh(every interval: Duration = .seconds(30)) async {
        await reload()
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { break }
            await reload()
        }
    }
}

struct HealthScoreView: View {
    @StateObject private var model = HealthScoreModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { await model.startAutoRefresh() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Health Score")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Eine Zahl 0-100. Sicherheit, Backup, Cleanup-Druck, Snapshots zusammengezählt.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
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
                        .foregroundStyle(MD4.SemColor.textPrimary)
                    Text("/ 100")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
            }
    }

    private func signals(_ signals: [HealthSignal]) -> some View {
        List {
            ForEach(signals) { sig in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sig.title)
                            .font(MD4.Typo.body)
                            .foregroundStyle(MD4.SemColor.textPrimary)
                        Text(sig.detail)
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.textSecondary)
                    }
                    Spacer()
                    Text("\(sig.earned)/\(sig.weight)")
                        .font(MD4.Typo.tabular(MD4.Typo.body))
                        .foregroundStyle(sig.earned == sig.weight
                                         ? MD4.SemColor.success
                                         : MD4.SemColor.warning)
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
