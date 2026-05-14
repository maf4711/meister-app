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
    /// 3. Extended Attributes: .DS_Store + ._* under user dirs
    /// 4. Empty user ~/.Trash
    func run() async {
        phaseLog.removeAll()
        bytesReclaimed = 0
        lastError = nil

        // 1. System Cleanup
        await runPhase(label: "System Cleanup", icon: "sparkles") { [self] in
            let scans = await systemCleanup.scanAll()
            let safe = Set(scans.filter { $0.category.safeDefault && $0.bytes > 0 }.map(\.category))
            guard !safe.isEmpty else { return 0 }
            let manifest = try await cleaner.clean(safe)
            return manifest.totalReclaimedBytes
        }

        // 2. Browser caches
        await runPhase(label: "Browser-Caches", icon: "safari") { [self] in
            let entries = await browserPrivacy.scan()
            let cachesOnly = entries.filter { $0.target == .cache }
            guard !cachesOnly.isEmpty else { return 0 }
            return await browserPrivacy.recycle(cachesOnly)
        }

        // 3. Extended attributes — .DS_Store + ._* (skip quarantine: needs explicit user consent)
        await runPhase(label: "Junk-Files (.DS_Store, ._*)", icon: "doc.badge.gearshape") { [self] in
            let cats = await xattrScanner.scan()
            let cleanable = cats.filter { $0.kind == .dsStore || $0.kind == .appleDouble }
            var total: Int64 = 0
            for cat in cleanable {
                total += await xattrScanner.clean(cat)
            }
            return total
        }

        // 4. Empty Trash
        await runPhase(label: "Papierkorb leeren", icon: "trash") { [self] in
            await emptyTrash()
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

    private func emptyTrash() async -> Int64 {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: trash,
                                                       includingPropertiesForKeys: [.fileAllocatedSizeKey],
                                                       options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for item in items {
            let bytes = (try? sizeOf(item)) ?? 0
            do {
                try fm.removeItem(at: item)
                total += bytes
            } catch {
                // Skip — locked / SIP-protected items just stay.
            }
        }
        return total
    }

    private func sizeOf(_ url: URL) throws -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try fm.attributesOfItem(atPath: url.path)
            return Int64((attrs[.size] as? NSNumber)?.int64Value ?? 0)
        }
        var total: Int64 = 0
        if let it = fm.enumerator(at: url,
                                   includingPropertiesForKeys: [.fileAllocatedSizeKey],
                                   options: [.skipsHiddenFiles]) {
            for case let f as URL in it {
                let s = (try? f.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0
                total += Int64(s)
            }
        }
        return total
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
            Text("Räumt System Cleanup safe-defaults + Browser-Caches + .DS_Store/._*-Junk + leert den Papierkorb. Items aus System-Cleanup landen erst im Trash und werden dann mit-geleert. History/Cookies/Bookmarks bleiben unangetastet.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Clean Alles")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Ein Klick → System-Cleanup + Browser-Caches + Junk-Files + Papierkorb. Erledigt.")
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
            Text("Fertig — \(model.bytesReclaimed.humanBytes) reclaimed")
                .font(MD4.Typo.title3)
                .foregroundStyle(MD4.SemColor.success)
            Text("Mit Undo Last Cleanup zurückholbar (außer Trash-Inhalt).")
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
        case .idle: return "System + Browser + Junk + Trash, alles in einem Lauf"
        case .running(let label): return label
        case .done: return "\(model.bytesReclaimed.humanBytes) reclaimed"
        }
    }
}

#Preview {
    AutoCleanAllView()
        .frame(width: 720, height: 600)
        .preferredColorScheme(.dark)
}
