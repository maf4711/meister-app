import SwiftUI
import AppKit
import MeradOSDesign3

/// One ips/crash file from ~/Library/Logs/DiagnosticReports/.
/// We do NOT parse the binary ips format — just expose name, size, age,
/// and let the user open it in Console.app.
struct CrashReport: Identifiable, Hashable {
    let id: String      // absolute file path
    let url: URL
    let processName: String
    let date: Date
    let sizeBytes: Int64
    let kind: Kind

    enum Kind: String {
        case crash = ".crash"
        case ips = ".ips"
        case spin = ".spin"
        case hang = ".hang"
        case diag = ".diag"
        case other = "other"

        var icon: String {
            switch self {
            case .crash, .ips: return "exclamationmark.octagon.fill"
            case .spin:        return "tornado"
            case .hang:        return "pause.circle"
            case .diag:        return "stethoscope"
            case .other:       return "doc"
            }
        }

        var color: Color {
            switch self {
            case .crash, .ips: return MD3.SemColor.error
            case .spin, .hang: return MD3.SemColor.warning
            default:           return MD3.SemColor.textSecondary
            }
        }
    }
}

actor CrashReportsReader {
    func read() async -> [CrashReport] {
        let fm = FileManager.default
        let dirs: [URL] = [
            URL(fileURLWithPath: NSString("~/Library/Logs/DiagnosticReports").expandingTildeInPath),
            URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"),
        ]
        var out: [CrashReport] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items {
                let ext = "." + url.pathExtension.lowercased()
                let kind = CrashReport.Kind(rawValue: ext) ?? .other
                guard kind != .other else { continue }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(values?.fileSize ?? 0)
                let date = values?.contentModificationDate ?? Date.distantPast
                let process = parseProcessName(from: url.lastPathComponent)
                out.append(CrashReport(
                    id: url.path,
                    url: url,
                    processName: process,
                    date: date,
                    sizeBytes: size,
                    kind: kind
                ))
            }
        }
        return out.sorted { $0.date > $1.date }
    }

    /// Crash files are named `Process-2024-01-31-153012.ips` (or with hostname).
    /// Take the leading prefix up to the first digit/date as the process name.
    nonisolated func parseProcessName(from filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        // First component before "_" or "-yyyy" pattern.
        if let range = stem.range(of: "[_-]\\d{4}", options: .regularExpression) {
            return String(stem[..<range.lowerBound])
        }
        return stem
    }
}

@MainActor
final class CrashReportsModel: ObservableObject {
    @Published var reports: [CrashReport] = []
    @Published var isLoading = false
    @Published var filter: Filter = .all
    private let reader = CrashReportsReader()

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Alle"
        case last7d = "Letzte 7 Tage"
        case last24h = "Letzte 24h"
        var id: String { rawValue }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.reports = await reader.read()
    }

    var visibleReports: [CrashReport] {
        let now = Date()
        switch filter {
        case .all:     return reports
        case .last24h: return reports.filter { now.timeIntervalSince($0.date) < 86_400 }
        case .last7d:  return reports.filter { now.timeIntervalSince($0.date) < 86_400 * 7 }
        }
    }

    /// Group by processName so a crashy app stands out instead of drowning the list.
    var grouped: [(String, [CrashReport])] {
        let groups = Dictionary(grouping: visibleReports, by: \.processName)
        return groups
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.1.count > $1.1.count }
    }

    var totalBytes: Int64 {
        visibleReports.reduce(0) { $0 + $1.sizeBytes }
    }

    func reveal(_ report: CrashReport) {
        NSWorkspace.shared.activateFileViewerSelecting([report.url])
    }

    /// Opens in the default handler — Console.app on stock macOS.
    func openInConsole(_ report: CrashReport) {
        NSWorkspace.shared.open(report.url)
    }
}

struct CrashReportsView: View {
    @StateObject private var model = CrashReportsModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            content
        }
        .background(MD3.SemColor.background)
        .task { if model.reports.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Crash Reports")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("~/Library/Logs/DiagnosticReports/. Gruppiert nach Prozess — top heißt Top-Crasher.")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            Picker("Zeitraum", selection: $model.filter) {
                ForEach(CrashReportsModel.Filter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.reports.isEmpty {
            ProgressView("Lese DiagnosticReports…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visibleReports.isEmpty {
            ContentUnavailableView(
                "Keine Crashes",
                systemImage: "checkmark.seal.fill",
                description: Text("Im gewählten Zeitraum hat sich nichts beschwert."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    HStack {
                        Image(systemName: "doc.on.doc.fill").foregroundStyle(MD3.SemColor.brandPrimary)
                        Text("\(model.visibleReports.count) Reports · \(model.totalBytes.humanBytes)")
                            .font(MD3.Typo.body)
                        Spacer()
                    }
                }
                ForEach(model.grouped, id: \.0) { process, reports in
                    Section {
                        ForEach(reports) { report in
                            row(report)
                        }
                    } header: {
                        HStack {
                            Text(process)
                                .font(MD3.Typo.headline)
                                .foregroundStyle(MD3.SemColor.textPrimary)
                            badge("\(reports.count)", reports.count > 3 ? MD3.SemColor.error : MD3.SemColor.warning)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ report: CrashReport) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: report.kind.icon)
                .foregroundStyle(report.kind.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.url.lastPathComponent)
                    .font(MD3.Typo.body)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(relativeDate(report.date))
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                    Text("·")
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textTertiary)
                    Text(report.sizeBytes.humanBytes)
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                }
            }
            Spacer()
            Button { model.openInConsole(report) } label: {
                Label("Console", systemImage: "terminal")
            }
            .buttonStyle(.borderless)
            Button { model.reveal(report) } label: {
                Label("Im Finder", systemImage: "folder")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(MD3.Typo.caption.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
