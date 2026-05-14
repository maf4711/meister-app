import SwiftUI
import AppKit
import MeradOSDesign4

struct XAttrCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let kind: Kind
    let urls: [URL]
    var totalBytes: Int64 = 0

    enum Kind {
        case dsStore        // .DS_Store files
        case appleDouble    // ._* files (resource forks)
        case quarantine     // files with com.apple.quarantine xattr
    }
}

actor ExtendedAttributesScanner {
    private let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func scan() async -> [XAttrCategory] {
        let scopes: [URL] = [
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("Movies"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }

        var ds: [URL] = []
        var appleDouble: [URL] = []
        var quarantine: [URL] = []

        for scope in scopes {
            walk(scope) { url, name in
                if name == ".DS_Store" {
                    ds.append(url)
                } else if name.hasPrefix("._") {
                    appleDouble.append(url)
                }
                if hasQuarantine(url) {
                    quarantine.append(url)
                }
            }
        }

        return [
            makeCategory(.dsStore, title: ".DS_Store", icon: "doc.fill", urls: ds),
            makeCategory(.appleDouble, title: "Apple-Double-Files (._*)", icon: "doc.on.doc", urls: appleDouble),
            makeCategory(.quarantine, title: "Quarantine-Flags", icon: "exclamationmark.shield", urls: quarantine),
        ]
    }

    /// Recycle (.DS_Store + ._*) or strip xattr (quarantine).
    @MainActor
    func clean(_ category: XAttrCategory) async -> Int64 {
        switch category.kind {
        case .dsStore, .appleDouble:
            let total = category.totalBytes
            let ok: Bool = await withCheckedContinuation { cont in
                NSWorkspace.shared.recycle(category.urls) { _, err in
                    cont.resume(returning: err == nil)
                }
            }
            return ok ? total : 0
        case .quarantine:
            var stripped = 0
            for url in category.urls {
                if stripQuarantine(url) { stripped += 1 }
            }
            return Int64(stripped)
        }
    }

    nonisolated func stripQuarantine(_ url: URL) -> Bool {
        let attr = "com.apple.quarantine"
        let result = url.path.withCString { p in
            attr.withCString { a in
                removexattr(p, a, 0)
            }
        }
        return result == 0
    }

    private nonisolated func walk(_ root: URL, found: (URL, String) -> Void) {
        let fm = FileManager.default
        guard let it = fm.enumerator(at: root,
                                      includingPropertiesForKeys: nil,
                                      options: [.skipsPackageDescendants],
                                      errorHandler: { _, _ in true }) else { return }
        for case let url as URL in it {
            found(url, url.lastPathComponent)
        }
    }

    private nonisolated func hasQuarantine(_ url: URL) -> Bool {
        let attr = "com.apple.quarantine"
        let len = url.path.withCString { p in
            attr.withCString { a in
                getxattr(p, a, nil, 0, 0, 0)
            }
        }
        return len > 0
    }

    private nonisolated func makeCategory(_ kind: XAttrCategory.Kind,
                                          title: String,
                                          icon: String,
                                          urls: [URL]) -> XAttrCategory {
        let total = urls.reduce(Int64(0)) { acc, u in
            let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
            let s = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            return acc + Int64(s)
        }
        return XAttrCategory(
            id: "\(kind)",
            title: title,
            icon: icon,
            kind: kind,
            urls: urls,
            totalBytes: total
        )
    }
}

@MainActor
final class ExtendedAttributesModel: ObservableObject {
    @Published var categories: [XAttrCategory] = []
    @Published var isScanning = false
    @Published var lastResult: String?
    private let scanner = ExtendedAttributesScanner()

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        self.categories = await scanner.scan()
    }

    func clean(_ category: XAttrCategory) async {
        let result = await scanner.clean(category)
        switch category.kind {
        case .dsStore, .appleDouble:
            lastResult = "\(category.title): \(result.humanBytes) recycled"
        case .quarantine:
            lastResult = "\(category.title): \(result) flags stripped"
        }
        await scan()
    }
}

struct ExtendedAttributesView: View {
    @StateObject private var model = ExtendedAttributesModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.categories.isEmpty { await model.scan() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Extended Attributes")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text(".DS_Store + ._* Files in den Trash, Quarantine-xattr stripped — keine Datei wird gelöscht außer Apple-Müll-Files.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
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
        if model.isScanning && model.categories.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(model.categories) { cat in
                        categoryCard(cat)
                    }
                    if let last = model.lastResult {
                        Text(last)
                            .font(MD4.Typo.caption)
                            .foregroundStyle(MD4.SemColor.success)
                    }
                }
                .padding(20)
            }
        }
    }

    private func categoryCard(_ c: XAttrCategory) -> some View {
        HStack {
            Image(systemName: c.icon).foregroundStyle(MD4.SemColor.brandPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title)
                    .font(MD4.Typo.body)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text(detailText(c))
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            Button(actionLabel(c)) {
                Task { await model.clean(c) }
            }
            .disabled(c.urls.isEmpty)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailText(_ c: XAttrCategory) -> String {
        switch c.kind {
        case .dsStore, .appleDouble:
            return "\(c.urls.count) files · \(c.totalBytes.humanBytes)"
        case .quarantine:
            return "\(c.urls.count) files mit Quarantine-xattr — Gatekeeper hat sie noch nicht freigegeben"
        }
    }

    private func actionLabel(_ c: XAttrCategory) -> String {
        switch c.kind {
        case .dsStore, .appleDouble: return "In Papierkorb"
        case .quarantine: return "Strip xattr"
        }
    }
}
