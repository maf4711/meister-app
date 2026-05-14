import SwiftUI
import AppKit
import MeradOSDesign4

struct LargeFilesView: View {
    @StateObject private var scanner = LargeFilesScanner()
    @State private var minMB: Double = 100
    @State private var olderThanDays: Int = 365
    @State private var requireOld: Bool = true
    @State private var selected: Set<LargeFileItem.ID> = []
    @State private var showConfirm = false
    @State private var lastReclaimed: Int64?
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider().background(MD4.SemColor.divider)
            content
            Divider().background(MD4.SemColor.divider)
            footer
        }
        .background(MD4.SemColor.background)
        .alert("Move \(selectedBytes.humanBytes) to Trash?",
               isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task { await trashSelected() }
            }
        } message: {
            Text("\(selected.count) file\(selected.count == 1 ? "" : "s"). Items go to ~/.Trash and can be restored.")
        }
        .alert("Error",
               isPresented: Binding(get: { errorText != nil },
                                    set: { if !$0 { errorText = nil } })) {
            Button("OK") { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    private var selectedBytes: Int64 {
        scanner.items
            .filter { selected.contains($0.id) }
            .reduce(0) { $0 + $1.bytes }
    }

    // MARK: controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Large & Old Files")
                        .font(MD4.Typo.title3)
                        .foregroundStyle(MD4.SemColor.textPrimary)
                    Text("Spotlight-indexed scan of Documents, Desktop, Downloads, Movies, Music, Pictures.")
                        .font(MD4.Typo.small)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
                Spacer()
            }
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text("Min")
                        .font(MD4.Typo.small)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                    Slider(value: $minMB, in: 10...2_000, step: 10)
                        .frame(width: 180)
                    Text("\(Int(minMB)) MB")
                        .font(MD4.Typo.tabular(MD4.Typo.small))
                        .foregroundStyle(MD4.SemColor.textPrimary)
                        .frame(width: 64, alignment: .leading)
                }
                Toggle(isOn: $requireOld) {
                    Text("Older than")
                        .font(MD4.Typo.small)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                }
                .toggleStyle(.checkbox)
                Stepper("\(olderThanDays) days",
                        value: $olderThanDays,
                        in: 30...3_650,
                        step: 30)
                    .font(MD4.Typo.small)
                    .disabled(!requireOld)
                Spacer()
                Button("Scan") {
                    selected = []
                    scanner.scan(minBytes: Int64(minMB) * 1_048_576,
                                 olderThanDays: requireOld ? olderThanDays : nil)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(scanner.isScanning)
            }
        }
        .padding(20)
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        if scanner.isScanning {
            VStack(spacing: 12) {
                ProgressView()
                Text("Querying Spotlight…")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if scanner.items.isEmpty {
            ContentUnavailableView("No matches",
                                   systemImage: "magnifyingglass",
                                   description: Text("Adjust thresholds and scan again."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(scanner.items) { item in
                    row(item)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ item: LargeFileItem) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { selected.contains(item.id) },
                set: { yes in
                    if yes { selected.insert(item.id) } else { selected.remove(item.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().interpolation(.high)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .font(MD4.Typo.body)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                    .lineLimit(1)
                Text(item.url.deletingLastPathComponent().path)
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(item.bytes.humanBytes)
                    .font(MD4.Typo.tabular(MD4.Typo.body))
                    .foregroundStyle(MD4.SemColor.textPrimary)
                if let date = item.freshness {
                    Text(LargeFilesView.relativeFormatter.localizedString(for: date, relativeTo: .now))
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textTertiary)
                }
            }
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    // MARK: footer

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                    .textCase(.uppercase)
                Text(selectedBytes.humanBytes)
                    .font(MD4.Typo.tabular(MD4.Typo.headline))
                    .foregroundStyle(MD4.SemColor.textPrimary)
            }
            Spacer()
            if let last = lastReclaimed {
                Text("Last clean: \(last.humanBytes)")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.success)
                    .padding(.trailing, 12)
            }
            Button("Move to Trash") { showConfirm = true }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(selected.isEmpty)
        }
        .padding(20)
    }

    private func trashSelected() async {
        let urls = scanner.items
            .filter { selected.contains($0.id) }
            .map(\.url)
        let bytes = selectedBytes
        let result = await withCheckedContinuation { (cont: CheckedContinuation<Error?, Never>) in
            NSWorkspace.shared.recycle(urls) { _, error in
                cont.resume(returning: error)
            }
        }
        if let err = result {
            errorText = err.localizedDescription
            return
        }
        lastReclaimed = bytes
        // Drop trashed items from the list.
        scanner.items.removeAll { selected.contains($0.id) }
        selected.removeAll()
    }
}

#Preview {
    LargeFilesView()
        .frame(width: 820, height: 560)
        .preferredColorScheme(.dark)
}
