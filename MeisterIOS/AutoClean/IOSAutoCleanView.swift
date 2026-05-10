import SwiftUI
import Photos
import MeradOSDesign3

@MainActor
final class IOSAutoCleanModel: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var phaseLog: [PhaseResult] = []
    @Published var photosScanned = false
    @Published var totalReclaimedBytes: Int64 = 0
    @Published var lastError: String?

    enum Phase: Equatable {
        case idle
        case scanning(String)
        case cleaning(String)
        case done
    }

    struct PhaseResult: Identifiable, Hashable {
        let id = UUID()
        let label: String
        let icon: String
        let bytes: Int64
        let count: Int
        let success: Bool
    }

    private let photosVM = PhotosViewModel()
    private let permissions = PermissionManager.shared

    var isRunning: Bool {
        switch phase {
        case .scanning, .cleaning: return true
        default: return false
        }
    }

    /// Run all safe-default iOS cleanups in sequence:
    /// 1. Photos: scan if needed, then auto-delete duplicate copies + screenshots + recordings + blurry
    /// 2. App Cache: clear Meister's own sandbox
    /// (Contacts dedup is opt-in only — too easy to merge wrong pairs.)
    func run() async {
        phaseLog.removeAll()
        totalReclaimedBytes = 0
        lastError = nil

        // 1a. Scan photos if not already scanned
        if !photosScanned && permissions.isPhotosAuthorized {
            phase = .scanning("Photos werden gescannt…")
            await photosVM.scan()
            photosScanned = true
        }

        // 1b. Auto-delete photo categories
        if permissions.isPhotosAuthorized {
            phase = .cleaning("Photos auto-delete…")
            let assets = collectReclaimablePhotos()
            let bytes = sizeOfPhotos(assets)
            if !assets.isEmpty {
                await photosVM.delete(assets)
                phaseLog.append(.init(label: "Photos auto-delete",
                                      icon: "photo.on.rectangle.angled",
                                      bytes: bytes,
                                      count: assets.count,
                                      success: true))
                totalReclaimedBytes += bytes
            } else {
                phaseLog.append(.init(label: "Photos — nichts zu tun",
                                      icon: "photo.on.rectangle.angled",
                                      bytes: 0,
                                      count: 0,
                                      success: true))
            }
        } else {
            phaseLog.append(.init(label: "Photos — keine Berechtigung",
                                  icon: "photo.on.rectangle.angled",
                                  bytes: 0,
                                  count: 0,
                                  success: false))
        }

        // 2. App Cache
        phase = .cleaning("App-Cache leeren…")
        let cacheBefore = await Task.detached { StorageReader.appCacheBytes() }.value
        do {
            try StorageReader.purgeAppCache()
            phaseLog.append(.init(label: "App-Cache",
                                  icon: "internaldrive",
                                  bytes: cacheBefore,
                                  count: 0,
                                  success: true))
            totalReclaimedBytes += cacheBefore
        } catch {
            phaseLog.append(.init(label: "App-Cache fehlgeschlagen",
                                  icon: "internaldrive",
                                  bytes: 0,
                                  count: 0,
                                  success: false))
            lastError = error.localizedDescription
        }

        phase = .done
    }

    private func collectReclaimablePhotos() -> [PHAsset] {
        var seen = Set<String>()
        var out: [PHAsset] = []
        let add: (PHAsset) -> Void = { a in
            if seen.insert(a.localIdentifier).inserted { out.append(a) }
        }
        for group in photosVM.duplicateGroups {
            // Keep the largest, drop the rest.
            let sorted = group.items.sorted { $0.sizeBytes > $1.sizeBytes }
            for copy in sorted.dropFirst() { add(copy.asset) }
        }
        photosVM.screenshots.forEach { add($0.asset) }
        photosVM.screenRecordings.forEach { add($0.asset) }
        photosVM.blurryPhotos.forEach { add($0.0.asset) }
        return out
    }

    private func sizeOfPhotos(_ assets: [PHAsset]) -> Int64 {
        var total: Int64 = 0
        let ids = Set(assets.map(\.localIdentifier))
        for item in photosVM.library where ids.contains(item.asset.localIdentifier) {
            total += item.sizeBytes
        }
        return total
    }
}

struct IOSAutoCleanView: View {
    @StateObject private var model = IOSAutoCleanModel()
    @StateObject private var launcher = AutoCleanLauncher.shared
    @State private var permissions = PermissionManager.shared
    @State private var showConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    heroButton
                    phaseList
                }
                .padding(20)
            }
            .navigationTitle("Auto-Clean")
            .background(MD3.SemColor.background)
            .alert("Alles automatisch erledigen?",
                   isPresented: $showConfirm) {
                Button("Abbrechen", role: .cancel) { }
                Button("Loslegen", role: .destructive) {
                    Task { await model.run() }
                }
            } message: {
                Text("Photos: Duplikate (Kopien), Screenshots, Screen-Recordings, Blurry → 'Recently Deleted' (30 Tage rückholbar). App-Cache: Meisters eigene Sandbox. Kontakte werden NICHT zusammengeführt — ist zu riskant ohne Review.")
            }
            // Shortcuts intent path: skip the confirm sheet — the user already
            // confirmed by saying "Hey Siri, Quick-Clean".
            .task(id: launcher.pendingAutoStart) {
                guard launcher.consume(), !model.isRunning else { return }
                await model.run()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Alles erledigen")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MD3.SemColor.textPrimary)
            Text("Photos auto-delete + App-Cache. Ein Tap.")
                .font(MD3.Typo.body)
                .foregroundStyle(MD3.SemColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroButton: some View {
        Button {
            showConfirm = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 32))
                    .symbolEffect(.pulse, isActive: model.isRunning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(buttonLabel)
                        .font(.system(size: 20, weight: .semibold))
                    Text(buttonSubtitle)
                        .font(MD3.Typo.caption)
                        .opacity(0.85)
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [MD3.SemColor.brandPrimary, MD3.SemColor.brandStrong],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: MD3.SemColor.brandPrimary.opacity(0.4), radius: 14, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(model.isRunning)
    }

    private var phaseList: some View {
        VStack(spacing: 10) {
            ForEach(model.phaseLog) { r in
                HStack(spacing: 10) {
                    Image(systemName: r.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(r.success ? MD3.SemColor.success : MD3.SemColor.warning)
                    Image(systemName: r.icon).foregroundStyle(MD3.SemColor.brandPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.label)
                            .font(MD3.Typo.body)
                            .foregroundStyle(MD3.SemColor.textPrimary)
                        if r.count > 0 {
                            Text("\(r.count) item\(r.count == 1 ? "" : "s")")
                                .font(MD3.Typo.caption)
                                .foregroundStyle(MD3.SemColor.textSecondary)
                        }
                    }
                    Spacer()
                    if r.bytes > 0 {
                        Text(r.bytes.humanBytes)
                            .font(MD3.Typo.tabular(MD3.Typo.body))
                            .foregroundStyle(MD3.SemColor.success)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MD3.SemColor.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if case .scanning(let label) = model.phase {
                phaseProgressRow(label)
            }
            if case .cleaning(let label) = model.phase {
                phaseProgressRow(label)
            }
            if model.phase == .done {
                Text("Fertig — \(model.totalReclaimedBytes.humanBytes) reclaimed")
                    .font(MD3.Typo.title3)
                    .foregroundStyle(MD3.SemColor.success)
                    .padding(.top, 4)
            }
        }
    }

    private func phaseProgressRow(_ label: String) -> some View {
        HStack {
            ProgressView().controlSize(.small)
            Text(label)
                .font(MD3.Typo.body)
                .foregroundStyle(MD3.SemColor.textPrimary)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var buttonLabel: String {
        switch model.phase {
        case .idle: return "Alles erledigen"
        case .scanning, .cleaning: return "Räume auf…"
        case .done: return "Nochmal"
        }
    }

    private var buttonSubtitle: String {
        switch model.phase {
        case .idle: return "Photos + App-Cache, automatisch"
        case .scanning(let l), .cleaning(let l): return l
        case .done: return "\(model.totalReclaimedBytes.humanBytes) reclaimed"
        }
    }
}

#Preview {
    IOSAutoCleanView()
}
