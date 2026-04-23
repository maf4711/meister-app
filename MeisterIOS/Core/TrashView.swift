import SwiftUI

struct TrashView: View {
    @State private var entries: [TrashEntry] = []

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing in Trash",
                    systemImage: "trash.slash",
                    description: Text("Contacts and events you delete via Meister appear here for 30 days.")
                )
            }
            ForEach(entries) { entry in
                HStack {
                    Image(systemName: entry.kind == .contact ? "person" : "calendar")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text(entry.summary)
                        Text("\(entry.kind.rawValue.capitalized) · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(remaining(entry))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Forget", role: .destructive) {
                        TrashStore.shared.remove(entry)
                        entries = TrashStore.shared.entries()
                    }
                }
            }
        }
        .navigationTitle("Trash (30d)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { entries = TrashStore.shared.entries() }
    }

    private func remaining(_ entry: TrashEntry) -> String {
        let remaining = entry.createdAt.timeIntervalSinceNow + 30 * 24 * 3600
        let days = Int(remaining / 86400)
        return "\(days)d left"
    }
}
