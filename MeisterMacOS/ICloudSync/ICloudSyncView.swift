import SwiftUI
import MeradOSDesign4

struct ICloudStatus: Equatable {
    let drivePath: String?
    let totalBytes: Int64
    let downloadedBytes: Int64
    let pendingBytes: Int64
    let signedIn: Bool
    let raw: String
}

actor ICloudSyncReader {
    private let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func read() async -> ICloudStatus {
        let drive = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        let exists = FileManager.default.fileExists(atPath: drive.path)
        let raw = exists ? scanDrive(drive) : (total: 0 as Int64, downloaded: 0 as Int64, pending: 0 as Int64, count: 0)
        let brctl = run("/usr/bin/brctl", ["status"])
        let signedIn = brctl.lowercased().contains("logged in")

        return ICloudStatus(
            drivePath: exists ? drive.path : nil,
            totalBytes: raw.total,
            downloadedBytes: raw.downloaded,
            pendingBytes: raw.pending,
            signedIn: signedIn,
            raw: brctl
        )
    }

    private nonisolated func scanDrive(_ url: URL) -> (total: Int64, downloaded: Int64, pending: Int64, count: Int) {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .ubiquitousItemDownloadingStatusKey,
        ]
        guard let it = fm.enumerator(at: url,
                                      includingPropertiesForKeys: Array(keys),
                                      options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                      errorHandler: { _, _ in true }) else {
            return (0, 0, 0, 0)
        }
        var total: Int64 = 0
        var downloaded: Int64 = 0
        var pending: Int64 = 0
        var count = 0

        for case let f as URL in it {
            guard let v = try? f.resourceValues(forKeys: keys),
                  let size = v.fileSize else { continue }
            let bytes = Int64(size)
            total += bytes
            count += 1
            switch v.ubiquitousItemDownloadingStatus {
            case .current?:
                downloaded += bytes
            case .downloaded?:
                downloaded += bytes
            case .notDownloaded?:
                pending += bytes
            default:
                downloaded += bytes
            }
        }
        return (total, downloaded, pending, count)
    }

    private nonisolated func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run(); p.waitUntilExit() } catch { return "" }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

@MainActor
final class ICloudSyncModel: ObservableObject {
    @Published var status: ICloudStatus?
    @Published var isLoading = false
    private let reader = ICloudSyncReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.status = await reader.read()
    }
}

struct ICloudSyncView: View {
    @StateObject private var model = ICloudSyncModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.status == nil { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("iCloud Drive")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("Sync-Status, downloaded vs nicht-downloaded Bytes, Account-Login.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if let s = model.status {
            ScrollView {
                VStack(spacing: 16) {
                    accountCard(s)
                    if s.drivePath != nil {
                        usageCard(s)
                    }
                }
                .padding(20)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func accountCard(_ s: ICloudStatus) -> some View {
        HStack(spacing: 14) {
            Image(systemName: s.signedIn ? "icloud.fill" : "icloud.slash")
                .foregroundStyle(s.signedIn ? MD4.SemColor.brandPrimary : MD4.SemColor.textSecondary)
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.signedIn ? "iCloud signed in" : "Not signed in to iCloud")
                    .font(MD4.Typo.title3)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                if let path = s.drivePath {
                    Text(path)
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                } else {
                    Text("iCloud Drive ist nicht aktiviert")
                        .font(MD4.Typo.caption)
                        .foregroundStyle(MD4.SemColor.warning)
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func usageCard(_ s: ICloudStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Speicher in iCloud Drive")
                .font(MD4.Typo.headline)
                .foregroundStyle(MD4.SemColor.textPrimary)
            HStack(spacing: 16) {
                metric("Total", s.totalBytes, color: MD4.SemColor.brandPrimary)
                metric("Downloaded", s.downloadedBytes, color: MD4.SemColor.success)
                metric("Pending", s.pendingBytes, color: MD4.SemColor.warning)
            }
            // Stacked bar
            GeometryReader { geo in
                let total = max(1, Double(s.totalBytes))
                let dlW = CGFloat(Double(s.downloadedBytes) / total) * geo.size.width
                let pendW = CGFloat(Double(s.pendingBytes) / total) * geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(MD4.SemColor.surfaceRaised)
                    HStack(spacing: 0) {
                        Capsule().fill(MD4.SemColor.success).frame(width: dlW)
                        Capsule().fill(MD4.SemColor.warning).frame(width: pendW)
                    }
                }
            }
            .frame(height: 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD4.SemColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metric(_ label: String, _ bytes: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(MD4.Typo.caption)
                .foregroundStyle(MD4.SemColor.textSecondary)
            Text(bytes.humanBytes)
                .font(MD4.Typo.tabular(MD4.Typo.body))
                .foregroundStyle(color)
        }
    }
}
