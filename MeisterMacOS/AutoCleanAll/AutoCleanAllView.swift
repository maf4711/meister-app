import SwiftUI
import AppKit
import MeradOSDesign4

/// "Alles erledigen" — runs every safe-default cleanup the Mac app supports
/// in one go. Single big button, phase-by-phase progress.
@MainActor
final class AutoCleanAllModel: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var bytesReclaimed: Int64 = 0
    @Published var phaseLog: [PhaseResult] = []
    @Published var lastError: String?

    enum Phase: Equatable {
        case idle
        case running(String)        // current step label
        case done
    }

    struct PhaseResult: Identifiable, Hashable {
        let id = UUID()
        let label: String
        let bytes: Int64
        let icon: String
        let success: Bool
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    private let systemCleanup = SystemCleanupScanner()
    private let cleaner = SystemCleanupCleaner()
    private let browserPrivacy = BrowserPrivacyCleaner()
    private let xattrScanner = ExtendedAttributesScanner()

    /// Run the full auto-clean pipeline.
    /// Phases (each independent, errors don't block the next):
    /// 1. System Cleanup (safe-default categories only — never Xcode Archives, never Mail Downloads)
    /// 2. Browser Privacy: Caches across all browsers (NOT history/cookies — opt-in only)
    /// 3. Extended Attributes: .DS_Store under user dirs
    /// Recycled files remain in Trash for recovery.
    func run() async {
        guard !isRunning else { return }
        phaseLog.removeAll()
        bytesReclaimed = 0
        lastError = nil

        // 1. System Cleanup
        await runPhase(label: "System Cleanup", icon: "sparkles") { [self] in
            let scans = await systemCleanup.scanAll()
            let safe = Set(scans.filter { $0.category.safeDefault && $0.bytes > 0 }.map(\.category))
            guard !safe.isEmpty else { return 0 }
            let manifest = try await cleaner.clean(safe)
            if manifest.entries.contains(where: { $0.error != nil }) {
                throw NSError(domain: "Meister.Cleanup", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "System-Cleanup nur teilweise abgeschlossen. Protokoll prüfen."])
            }
            return manifest.totalReclaimedBytes
        }

        // 2. Browser caches
        await runPhase(label: "Browser-Caches", icon: "safari") { [self] in
            let entries = await browserPrivacy.scan()
            let cachesOnly = entries.filter { $0.target == .cache }
            guard !cachesOnly.isEmpty else { return 0 }
            return await browserPrivacy.recycle(cachesOnly)
        }

        // 3. Extended attributes — .DS_Store (skip quarantine: needs explicit user consent)
        await runPhase(label: "Finder-Metadaten (.DS_Store)", icon: "doc.badge.gearshape") { [self] in
            let cats = await xattrScanner.scan()
            let cleanable = cats.filter { $0.kind == .dsStore }
            var total: Int64 = 0
            for cat in cleanable {
                total += await xattrScanner.clean(cat)
            }
            return total
        }

        phase = .done
    }

    private func runPhase(label: String, icon: String, work: () async throws -> Int64) async {
        phase = .running(label)
        do {
            let bytes = try await work()
            phaseLog.append(.init(label: label, bytes: bytes, icon: icon, success: true))
            bytesReclaimed += bytes
        } catch {
            phaseLog.append(.init(label: label, bytes: 0, icon: icon, success: false))
            lastError = "\(label): \(error.localizedDescription)"
        }
    }


}

struct AutoCleanAllView: View {
    @StateObject private var model = AutoCleanAllModel()
    @State private var showConfirm = false
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .sparkleBurst(trigger: celebrate, color: MD4.SemColor.success)
        .onChange(of: model.phase) { _, new in
            if new == .done && model.bytesReclaimed > 0 { celebrate.toggle() }
        }
        .alert("Alles auto-clean?",
               isPresented: $showConfirm) {
            Button("Abbrechen", role: .cancel) { }
            Button("Loslegen", role: .destructive) {
                Task { await model.run() }
            }
        } message: {
            Text("Bereinigt ausgewählte System- und Browser-Caches sowie Finder-Metadaten (.DS_Store). Recycelte Dateien bleiben zur Wiederherstellung im Papierkorb. Der Papierkorb wird nicht automatisch geleert.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Clean Alles")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("System-Cleanup, Browser-Caches und Metadaten. Der Papierkorb bleibt erhalten.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 24) {
            heroButton
            phaseList
            if let error = model.lastError {
                Text(error).foregroundStyle(MD4.SemColor.error).font(MD4.Typo.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var heroButton: some View {
        Button {
            showConfirm = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 36))
                    .symbolEffect(.pulse, isActive: model.isRunning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(buttonLabel)
                        .font(.system(size: 22, weight: .semibold))
                    Text(buttonSubtitle)
                        .font(MD4.Typo.caption)
                        .opacity(0.85)
                }
            }
            .padding(.horizontal, 36).padding(.vertical, 22)
            .frame(minWidth: 380)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [MD4.SemColor.brandPrimary, MD4.SemColor.brandStrong],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: ContinuousSquircle(cornerRadius: 22)
            )
            .shadow(color: MD4.SemColor.brandPrimary.opacity(0.5), radius: 22, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(model.isRunning)
    }

    private var phaseList: some View {
        VStack(spacing: 8) {
            ForEach(model.phaseLog) { result in
                phaseRow(result)
            }
            if case .running(let label) = model.phase {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(label)
                        .font(MD4.Typo.body)
                        .foregroundStyle(MD4.SemColor.textPrimary)
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: 520)
                .background(MD4.SemColor.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if model.phase == .done {
                summary
            }
        }
    }

    private func phaseRow(_ r: AutoCleanAllModel.PhaseResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: r.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(r.success ? MD4.SemColor.success : MD4.SemColor.warning)
            Image(systemName: r.icon).foregroundStyle(MD4.SemColor.brandPrimary)
            Text(r.label)
                .font(MD4.Typo.body)
                .foregroundStyle(MD4.SemColor.textPrimary)
            Spacer()
            Text(r.bytes > 0 ? r.bytes.humanBytes : (r.success ? "—" : "fail"))
                .font(MD4.Typo.tabular(MD4.Typo.body))
                .foregroundStyle(r.bytes > 0 ? MD4.SemColor.success : MD4.SemColor.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: 520)
        .background(MD4.SemColor.surfaceRaised.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var summary: some View {
        VStack(spacing: 4) {
            Text(model.lastError == nil ? "Fertig — \(model.bytesReclaimed.humanBytes) bearbeitet" : "Mit Fehlern abgeschlossen")
                .font(MD4.Typo.title3)
                .foregroundStyle(MD4.SemColor.success)
            Text("System-Cleanup über Undo rückgängig machen; weitere Dateien über den Papierkorb.")
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
        }
        .padding(.top, 8)
    }

    private var buttonLabel: String {
        switch model.phase {
        case .idle: return "Alles erledigen"
        case .running: return "Räume auf…"
        case .done: return "Nochmal"
        }
    }

    private var buttonSubtitle: String {
        switch model.phase {
        case .idle: return "System + Browser + Metadaten, Papierkorb bleibt erhalten"
        case .running(let label): return label
        case .done: return "\(model.bytesReclaimed.humanBytes) bearbeitet"
        }
    }
}

#Preview {
    AutoCleanAllView()
        .frame(width: 720, height: 600)
        .preferredColorScheme(.dark)
}
