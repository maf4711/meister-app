import SwiftUI
import MeradOSDesign3

@MainActor
final class BrowserPrivacyModel: ObservableObject {
    @Published var entries: [BrowserPrivacyEntry] = []
    @Published var selected: Set<String> = []
    @Published var isScanning = false
    @Published var lastReclaimed: Int64 = 0

    private let cleaner = BrowserPrivacyCleaner()

    var totalBytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }
    var selectedBytes: Int64 {
        entries.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        let result = await cleaner.scan()
        self.entries = result
        // Don't pre-select — privacy is opt-in.
    }

    func clean() async {
        let toRecycle = entries.filter { selected.contains($0.id) }
        guard !toRecycle.isEmpty else { return }
        let bytes = await cleaner.recycle(toRecycle)
        self.lastReclaimed = bytes
        await scan()
        self.selected.removeAll()
    }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) }
        else { selected.insert(id) }
    }

    func toggleBrowser(_ b: Browser) {
        let ids = entries.filter { $0.browser == b }.map(\.id)
        let allSelected = ids.allSatisfy { selected.contains($0) }
        if allSelected { ids.forEach { selected.remove($0) } }
        else { ids.forEach { selected.insert($0) } }
    }
}

struct BrowserPrivacyView: View {
    @StateObject private var model = BrowserPrivacyModel()
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
            Divider().background(MD3.SemColor.divider)
            footer
        }
        .background(MD3.SemColor.background)
        .task { if model.entries.isEmpty { await model.scan() } }
        .alert("History/Cookies in Papierkorb?",
               isPresented: $showConfirm) {
            Button("Abbrechen", role: .cancel) { }
            Button("In Papierkorb", role: .destructive) {
                Task { await model.clean() }
            }
        } message: {
            Text("\(model.selectedBytes.humanBytes) ausgewählt. Browser müssen für sauberes Resultat geschlossen sein, sonst schreiben sie die DBs neu.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Browser Privacy")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("History, Cookies, Downloads-Listen und Caches pro Browser. Alles in den Trash.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.scan() } } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning && model.entries.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(grouped(), id: \.0) { browser, items in
                    Section {
                        ForEach(items) { entry in
                            row(entry)
                        }
                    } header: {
                        HStack {
                            Image(systemName: browser.symbol)
                            Text(browser.displayName)
                                .font(MD3.Typo.headline)
                            Spacer()
                            Button("alles") { model.toggleBrowser(browser) }
                                .buttonStyle(.borderless)
                                .font(MD3.Typo.caption)
                            Text(items.reduce(0) { $0 + $1.bytes }.humanBytes)
                                .font(MD3.Typo.caption)
                                .foregroundStyle(MD3.SemColor.textSecondary)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func grouped() -> [(Browser, [BrowserPrivacyEntry])] {
        let dict = Dictionary(grouping: model.entries) { $0.browser }
        return Browser.allCases.compactMap { b -> (Browser, [BrowserPrivacyEntry])? in
            guard let items = dict[b], !items.isEmpty else { return nil }
            return (b, items.sorted { $0.target.rawValue < $1.target.rawValue })
        }
    }

    private func row(_ entry: BrowserPrivacyEntry) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { model.selected.contains(entry.id) },
                set: { _ in model.toggle(entry.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.target.label)
                    .font(MD3.Typo.body)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text(entry.path.lastPathComponent)
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Text(entry.bytes.humanBytes)
                .font(MD3.Typo.tabular(MD3.Typo.caption))
                .foregroundStyle(MD3.SemColor.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            Text("\(model.selected.count) ausgewählt · \(model.selectedBytes.humanBytes)")
                .font(MD3.Typo.caption)
                .foregroundStyle(MD3.SemColor.textSecondary)
            Spacer()
            if model.lastReclaimed > 0 {
                Text("Letzter Lauf: \(model.lastReclaimed.humanBytes)")
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.success)
                    .padding(.trailing, 12)
            }
            Button("In Papierkorb") {
                showConfirm = true
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.selected.isEmpty)
        }
        .padding(20)
    }
}

#Preview {
    BrowserPrivacyView()
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
