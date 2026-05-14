import SwiftUI
import MeradOSDesign4

@MainActor
final class TimeMachineModel: ObservableObject {
    @Published var status: TimeMachineStatus?
    @Published var snapshots: [LocalSnapshot] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let reader = TimeMachineReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        async let s = reader.status()
        async let snaps = reader.snapshots()
        self.status = await s
        self.snapshots = await snaps
    }

    func deleteSnapshot(_ snap: LocalSnapshot) async {
        let ok = await reader.deleteSnapshot(snap.name)
        if !ok { errorMessage = "Snapshot konnte nicht gelöscht werden: \(snap.name)" }
        await reload()
    }
}

struct TimeMachineView: View {
    @StateObject private var model = TimeMachineModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            statusCard
            Divider().background(MD4.SemColor.divider)
            snapshotList
        }
        .background(MD4.SemColor.background)
        .task { if model.status == nil { await model.reload() } }
        .alert("Fehler",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Time Machine & Snapshots")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Backup-Status + lokale APFS-Snapshots verwalten.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    @ViewBuilder
    private var statusCard: some View {
        if let s = model.status {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: s.isRunning ? "arrow.clockwise.icloud.fill" : "externaldrive.fill")
                        .foregroundStyle(s.isRunning ? MD4.SemColor.brandPrimary : MD4.SemColor.textSecondary)
                    Text(s.isRunning ? "Backup läuft gerade" : "Backup nicht aktiv")
                        .font(MD4.Typo.headline)
                        .foregroundStyle(MD4.SemColor.textPrimary)
                    Spacer()
                }
                if let last = s.lastBackupDate {
                    Text("Letztes Backup: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(MD4.Typo.small)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                } else {
                    Text("Letztes Backup: unbekannt")
                        .font(MD4.Typo.small)
                        .foregroundStyle(MD4.SemColor.warning)
                }
                if let dest = s.destination {
                    Text("Ziel: \(dest)")
                        .font(MD4.Typo.small)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var snapshotList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Lokale Snapshots (\(model.snapshots.count))")
                    .font(MD4.Typo.headline)
                Spacer()
                Text("APFS, auf der internen SSD")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            List {
                ForEach(model.snapshots) { snap in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snap.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? snap.name)
                                .font(MD4.Typo.body)
                                .foregroundStyle(MD4.SemColor.textPrimary)
                            Text(snap.name)
                                .font(MD4.Typo.caption)
                                .foregroundStyle(MD4.SemColor.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await model.deleteSnapshot(snap) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}

#Preview {
    TimeMachineView()
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
