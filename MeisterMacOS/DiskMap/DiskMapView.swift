import SwiftUI
import AppKit
import MeradOSDesign3

struct DiskNode: Identifiable, Hashable {
    let id: String           // path
    let name: String
    let url: URL
    let bytes: Int64
    let isDirectory: Bool
    let children: [DiskNode]

    var directBytes: Int64 {
        // For dirs: sum direct file children's bytes (not subdirs)
        children.filter { !$0.isDirectory }.reduce(0) { $0 + $1.bytes }
    }
}

actor DiskMapScanner {
    /// Recursive size scan with depth limit. Each depth level groups files
    /// vs subdirectories; subdirectories are recursed up to maxDepth.
    func scan(_ root: URL, maxDepth: Int = 2) async -> DiskNode {
        await Task.detached { [self] in scanSync(root, depth: 0, maxDepth: maxDepth) }.value
    }

    nonisolated private func scanSync(_ url: URL, depth: Int, maxDepth: Int) -> DiskNode {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return emptyNode(url)
        }

        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let bytes = Int64((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
            return DiskNode(id: url.path,
                            name: url.lastPathComponent,
                            url: url,
                            bytes: bytes,
                            isDirectory: false,
                            children: [])
        }

        // Directory: enumerate immediate children
        let entries = (try? fm.contentsOfDirectory(at: url,
                                                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                    options: [.skipsHiddenFiles])) ?? []

        var children: [DiskNode] = []
        var totalBytes: Int64 = 0

        for child in entries {
            let v = try? child.resourceValues(forKeys: [.isDirectoryKey])
            if v?.isDirectory == true {
                if depth < maxDepth {
                    let node = scanSync(child, depth: depth + 1, maxDepth: maxDepth)
                    children.append(node)
                    totalBytes += node.bytes
                } else {
                    // Don't recurse further but still compute total via fast walker
                    let bytes = fastSize(at: child)
                    children.append(DiskNode(id: child.path,
                                             name: child.lastPathComponent,
                                             url: child,
                                             bytes: bytes,
                                             isDirectory: true,
                                             children: []))
                    totalBytes += bytes
                }
            } else {
                let attrs = try? fm.attributesOfItem(atPath: child.path)
                let bytes = Int64((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
                children.append(DiskNode(id: child.path,
                                         name: child.lastPathComponent,
                                         url: child,
                                         bytes: bytes,
                                         isDirectory: false,
                                         children: []))
                totalBytes += bytes
            }
        }
        children.sort { $0.bytes > $1.bytes }
        return DiskNode(id: url.path,
                        name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                        url: url,
                        bytes: totalBytes,
                        isDirectory: true,
                        children: children)
    }

    nonisolated private func fastSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let it = fm.enumerator(at: url,
                                      includingPropertiesForKeys: [.fileAllocatedSizeKey],
                                      options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                      errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in it {
            let s = (try? f.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0
            total += Int64(s)
        }
        return total
    }

    nonisolated private func emptyNode(_ url: URL) -> DiskNode {
        DiskNode(id: url.path, name: url.lastPathComponent, url: url,
                 bytes: 0, isDirectory: false, children: [])
    }
}

@MainActor
final class DiskMapModel: ObservableObject {
    @Published var rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var root: DiskNode?
    @Published var path: [DiskNode] = []        // breadcrumb path from root
    @Published var isScanning = false
    private let scanner = DiskMapScanner()

    var current: DiskNode? {
        path.last ?? root
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        let r = await scanner.scan(rootURL, maxDepth: 2)
        self.root = r
        self.path = []
    }

    func drill(into node: DiskNode) {
        if node.isDirectory && !node.children.isEmpty {
            path.append(node)
        }
    }

    func drillUp() {
        if !path.isEmpty { path.removeLast() }
    }

    func reset() { path.removeAll() }
}

struct DiskMapView: View {
    @StateObject private var model = DiskMapModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            breadcrumbs
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
        .task { if model.root == nil { await model.scan() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Map")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("Treemap-Drilldown durch dein Home-Verzeichnis. Click → eine Ebene tiefer.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.scan() } } label: {
                Label(model.isScanning ? "Scanne…" : "Scan", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning)
        }
        .padding(20)
    }

    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            Button {
                model.reset()
            } label: {
                Label("Home", systemImage: "house")
            }
            .buttonStyle(.borderless)
            ForEach(model.path) { node in
                Image(systemName: "chevron.right")
                    .foregroundStyle(MD3.SemColor.textTertiary)
                    .font(.caption)
                Button(node.name) {
                    if let i = model.path.firstIndex(of: node) {
                        model.path = Array(model.path.prefix(i + 1))
                    }
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            if let cur = model.current {
                Text(cur.bytes.humanBytes)
                    .font(MD3.Typo.tabular(MD3.Typo.caption))
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning && model.root == nil {
            ProgressView("Scanne Home-Verzeichnis…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let cur = model.current {
            GeometryReader { geo in
                treemap(node: cur, in: CGRect(origin: .zero, size: geo.size))
            }
            .padding(8)
        }
    }

    /// Squarified-treemap-light: layout children left-to-right by relative size,
    /// fall back to vertical strips when width-to-height ratio gets ugly.
    private func treemap(node: DiskNode, in rect: CGRect) -> some View {
        let total = max(1, Double(node.bytes))
        let visible = node.children.prefix(40).filter { $0.bytes > 0 }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(layout(items: Array(visible), total: total, in: rect).enumerated()), id: \.offset) { idx, placement in
                tile(node: placement.node, frame: placement.rect)
            }
        }
    }

    private func tile(node: DiskNode, frame: CGRect) -> some View {
        let isLargeEnough = frame.width > 60 && frame.height > 36
        return Button {
            if node.isDirectory && !node.children.isEmpty {
                model.drill(into: node)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(colorForName(node.name).opacity(0.85))
                if isLargeEnough {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: node.isDirectory ? "folder" : "doc")
                                .font(.caption)
                            Text(node.name)
                                .font(MD3.Typo.caption.bold())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Text(node.bytes.humanBytes)
                            .font(MD3.Typo.caption)
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    private struct Placement {
        let node: DiskNode
        let rect: CGRect
    }

    /// Strip-layout: pack rows of varying width based on cumulative size.
    private func layout(items: [DiskNode], total: Double, in rect: CGRect) -> [Placement] {
        var out: [Placement] = []
        var cursor = rect
        var i = 0
        while i < items.count, cursor.width > 4, cursor.height > 4 {
            let useVertical = cursor.width >= cursor.height
            let stripLength = useVertical ? cursor.width : cursor.height
            let crossSize = useVertical ? cursor.height : cursor.width

            // Take as many items as fit nicely in this strip — at most 3 per strip
            // for readability.
            var strip: [DiskNode] = []
            var stripBytes: Double = 0
            let stripBudget = items[i...].prefix(3)
            for n in stripBudget {
                strip.append(n)
                stripBytes += Double(n.bytes)
            }
            // Strip's allocated cross-axis size proportional to stripBytes / remaining
            let remainingBytes = items[i...].reduce(Double(0)) { $0 + Double($1.bytes) }
            let cross = CGFloat(stripBytes / max(1, remainingBytes)) * crossSize

            // Lay out within strip
            var inner = useVertical
                ? CGRect(x: cursor.minX, y: cursor.minY, width: cursor.width, height: cross)
                : CGRect(x: cursor.minX, y: cursor.minY, width: cross, height: cursor.height)
            let stripCursor = inner
            var stripPos: CGFloat = useVertical ? stripCursor.minX : stripCursor.minY

            for n in strip {
                let portion = CGFloat(Double(n.bytes) / max(1, stripBytes)) * stripLength
                let r: CGRect = useVertical
                    ? CGRect(x: stripPos, y: stripCursor.minY, width: portion, height: stripCursor.height)
                    : CGRect(x: stripCursor.minX, y: stripPos, width: stripCursor.width, height: portion)
                out.append(Placement(node: n, rect: r.insetBy(dx: 1, dy: 1)))
                stripPos += portion
            }
            i += strip.count
            // Advance cursor past the consumed strip
            if useVertical {
                cursor = CGRect(x: cursor.minX, y: cursor.minY + cross, width: cursor.width, height: cursor.height - cross)
            } else {
                cursor = CGRect(x: cursor.minX + cross, y: cursor.minY, width: cursor.width - cross, height: cursor.height)
            }
            _ = inner
        }
        return out
    }

    /// Stable-ish color per file/dir name — hash → hue.
    private func colorForName(_ name: String) -> Color {
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.55)
    }
}
