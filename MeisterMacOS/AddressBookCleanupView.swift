import SwiftUI

struct AddressBookCleanupView: View {
    @StateObject private var model = AddressBookCleanupModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.sources.isEmpty && !model.isScanning {
                placeholder
            } else {
                sourceList
            }
            Divider()
            actionBar
        }
        .task { await model.scan() }
        .alert("Confirm cleanup",
               isPresented: $model.confirmCleanup,
               actions: { cleanupConfirmActions },
               message: { Text(model.cleanupPreview ?? "") })
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AddressBook Cleanup").font(.title2).bold()
                Text("Scans `~/Library/Application Support/AddressBook/Sources/` for bloated CardDAV sources and corrupt sync state.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.scan() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning)
        }
        .padding(20)
    }

    private var placeholder: some View {
        VStack {
            Spacer()
            ProgressView("Scanning AddressBook…")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sourceList: some View {
        Table(model.sources) {
            TableColumn("UUID") { source in
                Text(source.shortID).font(.system(.body, design: .monospaced))
            }
            TableColumn("Size") { source in
                Text(source.humanSize).monospacedDigit()
            }
            TableColumn("Account") { source in
                Text(source.account ?? "—").foregroundStyle(.secondary)
            }
            TableColumn("Last Event") { source in
                Text(source.lastMigrationEvent ?? "no migration.log")
                    .font(.caption)
                    .foregroundStyle(source.hasDestructiveMarker ? .red : .secondary)
                    .lineLimit(2)
            }
        }
    }

    private var actionBar: some View {
        HStack {
            if let largest = model.largestSource {
                Label("Largest: \(largest.humanSize) — \(largest.shortID)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(largest.sizeBytes > 500_000_000 ? .orange : .secondary)
            }
            Spacer()
            Button("Export vCard…") { Task { await model.exportVCard() } }
            Button("Clean up…") { model.requestCleanup() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.largestSource == nil)
        }
        .padding(16)
    }

    @ViewBuilder
    private var cleanupConfirmActions: some View {
        Button("Cancel", role: .cancel) { model.confirmCleanup = false }
        Button("Proceed", role: .destructive) {
            Task { await model.runCleanup() }
        }
    }
}
