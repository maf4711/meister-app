import SwiftUI
import MeradOSDesign4

@MainActor
final class BloatwareModel: ObservableObject {
    @Published var findings: [BloatFinding] = []
    @Published var selected: Set<BloatFinding.ID> = []
    @Published var isScanning = false
    @Published var isKilling = false
    @Published var lastManifest: BloatKillManifest?
    @Published var errorMessage: String?
    @Published var filterSeverity: BloatFinding.Severity?

    private let scanner = BloatwareScanner()
    private let cleaner = BloatwareCleaner()

    var filtered: [BloatFinding] {
        guard let f = filterSeverity else { return findings }
        return findings.filter { $0.severity == f }
    }

    var selectedFindings: [BloatFinding] {
        findings.filter { selected.contains($0.id) }
    }

    var p0Count: Int { findings.filter { $0.severity == .p0 }.count }
    var p1Count: Int { findings.filter { $0.severity == .p1 }.count }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        let scanner = self.scanner
        let result = await withCheckedContinuation { (cont: CheckedContinuation<[BloatFinding], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: scanner.scanAll())
            }
        }
        self.findings = result
        // Pre-select P0 only (safe default)
        self.selected = Set(result.filter { $0.severity == .p0 }.map(\.id))
    }

    func toggle(_ f: BloatFinding) {
        if selected.contains(f.id) {
            selected.remove(f.id)
        } else {
            selected.insert(f.id)
        }
    }

    func selectAllP0() {
        selected = Set(findings.filter { $0.severity == .p0 }.map(\.id))
    }

    func killSelected() async {
        let chosen = selectedFindings
        guard !chosen.isEmpty else { return }
        isKilling = true
        defer { isKilling = false }
        do {
            let manifest = try await cleaner.kill(chosen)
            self.lastManifest = manifest
            await scan()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

struct BloatwareView: View {
    @StateObject private var model = BloatwareModel()
    @State private var showConfirm = false
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            severityFilter
            Divider().background(MD4.SemColor.divider)
            content
            Divider().background(MD4.SemColor.divider)
            footer
        }
        .background(MD4.SemColor.background)
        .sparkleBurst(trigger: celebrate, color: MD4.SemColor.success)
        .task {
            if model.findings.isEmpty { await model.scan() }
        }
        .onChange(of: model.lastManifest?.quarantinedCount) { _, new in
            if (new ?? 0) > 0 { celebrate.toggle() }
        }
        .alert("Selected items to quarantine?",
               isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Quarantine", role: .destructive) {
                Task { await model.killSelected() }
            }
        } message: {
            Text("\(model.selectedFindings.count) items → ~/.meister/bloatware-quarantine (reversible). System paths skipped.")
        }
        .alert("Error",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bloatware Remover")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Catalog scan: junk apps, orphan LaunchAgents, noisy updaters. Kill only after confirm → quarantine.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            Button {
                Task { await model.scan() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning || model.isKilling)
        }
        .padding(20)
    }

    private var severityFilter: some View {
        HStack(spacing: 8) {
            chip("Alle", nil)
            chip("P0 \(model.p0Count)", .p0)
            chip("P1 \(model.p1Count)", .p1)
            Spacer()
            Button("Select P0") { model.selectAllP0() }
                .font(MD4.Typo.caption)
                .disabled(model.p0Count == 0)
            Text("\(model.filtered.count) items")
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func chip(_ label: String, _ sev: BloatFinding.Severity?) -> some View {
        let active = model.filterSeverity == sev
        return Button(label) { model.filterSeverity = sev }
            .font(MD4.Typo.caption)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(active ? MD4.SemColor.brandPrimary.opacity(0.2) : Color.clear,
                        in: Capsule())
            .foregroundStyle(active ? MD4.SemColor.brandPrimary : MD4.SemColor.textSecondary)
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning && model.findings.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning…")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.findings.isEmpty {
            ContentUnavailableView(
                "No bloat found",
                systemImage: "checkmark.shield",
                description: Text("Catalog-matched junk not present. KEEP list protects Apple, meradOS, dev tools.")
            )
        } else {
            List {
                ForEach(model.filtered) { f in
                    row(f)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ f: BloatFinding) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { model.selected.contains(f.id) },
                set: { _ in model.toggle(f) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    severityBadge(f.severity)
                    Text(f.name)
                        .font(MD4.Typo.body)
                        .foregroundStyle(MD4.SemColor.textPrimary)
                        .lineLimit(1)
                    Text(f.kind.rawValue)
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textTertiary)
                }
                Text(f.detail)
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                    .lineLimit(2)
                Text(f.path)
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if f.bytes > 0 {
                Text(f.bytes.humanBytes)
                    .font(MD4.Typo.tabular(MD4.Typo.caption))
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func severityBadge(_ sev: BloatFinding.Severity) -> some View {
        let color: Color = {
            switch sev {
            case .p0: return .red
            case .p1: return .orange
            case .p2: return .yellow
            }
        }()
        return Text(sev.rawValue)
            .font(MD4.Typo.caption.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                    .textCase(.uppercase)
                Text("\(model.selectedFindings.count)")
                    .font(MD4.Typo.tabular(MD4.Typo.headline))
                    .foregroundStyle(MD4.SemColor.textPrimary)
            }
            Spacer()
            if let m = model.lastManifest {
                Text("Last: \(m.quarantinedCount) quarantined")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.success)
                    .padding(.trailing, 12)
            }
            Button {
                showConfirm = true
            } label: {
                if model.isKilling {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Quarantining…")
                    }
                } else {
                    Text("Quarantine selected")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.selected.isEmpty || model.isKilling || model.isScanning)
        }
        .padding(20)
    }
}

#Preview {
    BloatwareView()
}
