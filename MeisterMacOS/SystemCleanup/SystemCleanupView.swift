import SwiftUI
import MeradOSDesign3

@MainActor
final class SystemCleanupModel: ObservableObject {
    @Published var scans: [CategoryScan] = []
    @Published var selected: Set<SystemCleanupCategory> = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var lastManifest: CleanupManifest?
    @Published var errorMessage: String?

    private let scanner = SystemCleanupScanner()
    private let cleaner = SystemCleanupCleaner()

    var totalSelectedBytes: Int64 {
        scans
            .filter { selected.contains($0.category) }
            .reduce(0) { $0 + $1.bytes }
    }

    var totalAvailableBytes: Int64 {
        scans.reduce(0) { $0 + $1.bytes }
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        let result = await scanner.scanAll()
        self.scans = result
        // Pre-select safe defaults — only categories with bytes > 0.
        self.selected = Set(
            result.filter { $0.bytes > 0 && $0.category.safeDefault }
                  .map { $0.category }
        )
    }

    func toggle(_ category: SystemCleanupCategory) {
        if selected.contains(category) {
            selected.remove(category)
        } else {
            selected.insert(category)
        }
    }

    func clean() async {
        guard !selected.isEmpty else { return }
        isCleaning = true
        defer { isCleaning = false }
        do {
            let manifest = try await cleaner.clean(selected)
            self.lastManifest = manifest
            // Refresh scan to reflect new sizes.
            await scan()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

struct SystemCleanupView: View {
    @StateObject private var model = SystemCleanupModel()
    @State private var showConfirm = false
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
            Divider().background(MD3.SemColor.divider)
            footer
        }
        .background(MD3.SemColor.background)
        .sparkleBurst(trigger: celebrate, color: MD3.SemColor.success)
        .task {
            if model.scans.isEmpty { await model.scan() }
        }
        .onChange(of: model.lastManifest?.totalReclaimedBytes) { _, new in
            if (new ?? 0) > 0 { celebrate.toggle() }
        }
        .alert("Send selected items to Trash?",
               isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Move to Trash", role: .destructive) {
                Task { await model.clean() }
            }
        } message: {
            Text("\(model.totalSelectedBytes.humanBytes) across \(model.selected.count) categories. Items go to ~/.Trash and can be restored. Trash itself is emptied directly.")
        }
        .alert("Cleanup error",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("System Cleanup")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("Caches, logs, and dev junk that the system regenerates on demand.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Button {
                Task { await model.scan() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning || model.isCleaning)
        }
        .padding(20)
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        if model.isScanning && model.scans.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning…")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(model.scans) { scan in
                    row(for: scan)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(for scan: CategoryScan) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { model.selected.contains(scan.category) },
                set: { _ in model.toggle(scan.category) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(scan.bytes == 0)

            Image(systemName: scan.category.symbol)
                .frame(width: 24)
                .foregroundStyle(MD3.SemColor.brandPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text(scan.category.title)
                    .font(MD3.Typo.body)
                    .foregroundStyle(scan.bytes == 0
                                     ? MD3.SemColor.textTertiary
                                     : MD3.SemColor.textPrimary)
                if scan.itemCount > 0 {
                    Text("\(scan.itemCount) item\(scan.itemCount == 1 ? "" : "s")")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                }
            }
            Spacer()
            Text(scan.bytes == 0 ? "—" : scan.bytes.humanBytes)
                .font(MD3.Typo.tabular(MD3.Typo.body))
                .foregroundStyle(MD3.SemColor.textSecondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected")
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
                    .textCase(.uppercase)
                Text(model.totalSelectedBytes.humanBytes)
                    .font(MD3.Typo.tabular(MD3.Typo.headline))
                    .foregroundStyle(MD3.SemColor.textPrimary)
            }
            Spacer()
            if let manifest = model.lastManifest {
                Text("Last clean: \(manifest.totalReclaimedBytes.humanBytes)")
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.success)
                    .padding(.trailing, 12)
            }
            Button {
                showConfirm = true
            } label: {
                if model.isCleaning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Cleaning…")
                    }
                } else {
                    Text("Clean")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.selected.isEmpty || model.isCleaning || model.isScanning)
        }
        .padding(20)
    }
}

#Preview {
    SystemCleanupView()
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
