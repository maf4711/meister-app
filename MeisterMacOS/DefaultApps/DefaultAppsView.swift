import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MeradOSDesign3

struct DefaultAppHandler: Identifiable, Hashable {
    let id: String
    let label: String
    let uti: UTType
    let appBundleID: String?
    let appName: String?
    let appURL: URL?
}

actor DefaultAppsReader {
    /// Common file types most users care about reassigning.
    static let common: [(label: String, uti: UTType)] = [
        ("PDF",                .pdf),
        ("HTML",               .html),
        ("Plain Text",         .plainText),
        ("Markdown",           UTType(filenameExtension: "md", conformingTo: .text) ?? .text),
        ("PNG Image",          .png),
        ("JPEG Image",         .jpeg),
        ("SVG",                UTType("public.svg-image") ?? .image),
        ("HEIC",               .heic),
        ("MP4 Video",          .mpeg4Movie),
        ("MOV Video",          .quickTimeMovie),
        ("MP3 Audio",          .mp3),
        ("WAV Audio",          .wav),
        ("ZIP Archive",        .zip),
        ("Tar Archive",        UTType("public.tar-archive") ?? .archive),
        ("Source Code (Swift)", UTType(filenameExtension: "swift", conformingTo: .sourceCode) ?? .sourceCode),
        ("JSON",               .json),
        ("XML",                .xml),
        ("CSV",                .commaSeparatedText),
    ]

    func read() async -> [DefaultAppHandler] {
        Self.common.compactMap { entry -> DefaultAppHandler? in
            let bundleURL = NSWorkspace.shared.urlForApplication(toOpen: entry.uti)
            let bundle = bundleURL.flatMap { Bundle(url: $0) }
            return DefaultAppHandler(
                id: entry.uti.identifier,
                label: entry.label,
                uti: entry.uti,
                appBundleID: bundle?.bundleIdentifier,
                appName: bundle?.infoDictionary?["CFBundleName"] as? String
                       ?? bundleURL?.deletingPathExtension().lastPathComponent,
                appURL: bundleURL
            )
        }
    }
}

@MainActor
final class DefaultAppsModel: ObservableObject {
    @Published var entries: [DefaultAppHandler] = []
    @Published var isLoading = false
    private let reader = DefaultAppsReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.entries = await reader.read()
    }
}

struct DefaultAppsView: View {
    @StateObject private var model = DefaultAppsModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            list
        }
        .background(MD3.SemColor.background)
        .task { if model.entries.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Default Apps")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("Welche App öffnet welchen Filetyp. Get Info → Open With benutzen, um zu ändern.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    private var list: some View {
        List(model.entries) { entry in
            HStack(spacing: 12) {
                if let url = entry.appURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .foregroundStyle(MD3.SemColor.textTertiary)
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.label)
                        .font(MD3.Typo.body)
                        .foregroundStyle(MD3.SemColor.textPrimary)
                    Text(entry.uti.identifier)
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.appName ?? "—")
                        .font(MD3.Typo.body)
                        .foregroundStyle(MD3.SemColor.textPrimary)
                    if let bid = entry.appBundleID {
                        Text(bid)
                            .font(MD3.Typo.caption)
                            .foregroundStyle(MD3.SemColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                if let url = entry.appURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help("App im Finder anzeigen")
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    DefaultAppsView()
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
