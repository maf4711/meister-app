import SwiftUI
import AppKit
import MeradOSDesign4

/// One row of `mdutil -as` output. The CLI prints one line per volume:
///   /System/Volumes/Data:
///       Indexing enabled.
struct SpotlightVolume: Identifiable, Hashable {
    let id: String        // mount path
    let path: String
    let status: Status
    let raw: String

    enum Status: String {
        case enabled = "Indexing enabled"
        case disabled = "Indexing disabled"
        case noIndex = "No index"
        case error = "Error"
        case unknown = "Unknown"

        var color: Color {
            switch self {
            case .enabled:   return MD4.SemColor.success
            case .disabled:  return MD4.SemColor.warning
            case .noIndex:   return MD4.SemColor.warning
            case .error:     return MD4.SemColor.error
            case .unknown:   return MD4.SemColor.textTertiary
            }
        }

        var icon: String {
            switch self {
            case .enabled:   return "magnifyingglass.circle.fill"
            case .disabled:  return "magnifyingglass.circle"
            case .noIndex:   return "questionmark.circle"
            case .error:     return "exclamationmark.triangle.fill"
            case .unknown:   return "circle.dashed"
            }
        }
    }
}

actor SpotlightReader {
    func read() async -> [SpotlightVolume] {
        let raw = run("/usr/bin/mdutil", ["-as"])
        return parse(raw)
    }

    nonisolated func parse(_ raw: String) -> [SpotlightVolume] {
        var out: [SpotlightVolume] = []
        var pending: String?
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            // Volume lines end with a colon and are not indented.
            if s.hasSuffix(":") && !s.hasPrefix("\t") && !s.hasPrefix(" ") {
                pending = String(s.dropLast())  // drop trailing ":"
            } else if let path = pending {
                let trimmed = s.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                let status = Self.classify(trimmed)
                out.append(SpotlightVolume(id: path, path: path, status: status, raw: trimmed))
                pending = nil
            }
        }
        return out
    }

    private static func classify(_ line: String) -> SpotlightVolume.Status {
        let lower = line.lowercased()
        if lower.contains("indexing enabled") { return .enabled }
        if lower.contains("indexing disabled") || lower.contains("indexing and searching disabled") { return .disabled }
        if lower.contains("no index") { return .noIndex }
        if lower.contains("error") { return .error }
        return .unknown
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
final class SpotlightIndexModel: ObservableObject {
    @Published var volumes: [SpotlightVolume] = []
    @Published var isLoading = false
    private let reader = SpotlightReader()

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.volumes = await reader.read()
    }

    /// Anything not in `.enabled` is something the user might want to know about.
    var problemVolumes: [SpotlightVolume] {
        volumes.filter { $0.status != .enabled }
    }

    func copyRebuildCommand(for path: String) {
        // Rebuilding requires sudo. We never run sudo from the app.
        let cmd = "sudo mdutil -E \"\(path)\""
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(cmd, forType: .string)
    }

    func copyEnableCommand(for path: String) {
        let cmd = "sudo mdutil -i on \"\(path)\""
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(cmd, forType: .string)
    }
}

struct SpotlightIndexView: View {
    @StateObject private var model = SpotlightIndexModel()
    @State private var copied: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            content
        }
        .background(MD4.SemColor.background)
        .task { if model.volumes.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Spotlight Index Audit")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("mdutil -as. Rebuild- und Enable-Kommandos werden in die Zwischenablage kopiert (brauchen sudo).")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            if !model.problemVolumes.isEmpty {
                badge("\(model.problemVolumes.count) Auffälligkeiten", MD4.SemColor.warning)
            } else if !model.volumes.isEmpty {
                badge("\(model.volumes.count) Volumes OK", MD4.SemColor.success)
            }
            Button { Task { await model.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.volumes.isEmpty {
            ProgressView("Frage mdutil…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.volumes.isEmpty {
            ContentUnavailableView(
                "Keine Volumes gefunden",
                systemImage: "magnifyingglass.circle",
                description: Text("mdutil -as lieferte keine Daten zurück."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.volumes) { v in
                row(v)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ v: SpotlightVolume) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: v.status.icon).foregroundStyle(v.status.color)
                Text(v.path)
                    .font(MD4.Typo.body)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                    .textSelection(.enabled)
                Spacer()
                Text(v.status.rawValue)
                    .font(MD4.Typo.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(v.status.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(v.status.color)
            }
            HStack(spacing: 12) {
                Text(v.raw)
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.textSecondary)
                    .lineLimit(1)
                Spacer()
                if v.status == .disabled {
                    Button {
                        model.copyEnableCommand(for: v.path)
                        markCopied(v.path)
                    } label: {
                        Label(copied == v.path ? "Kopiert!" : "Enable-Cmd",
                              systemImage: copied == v.path ? "checkmark" : "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                }
                if v.status == .enabled || v.status == .noIndex || v.status == .error {
                    Button {
                        model.copyRebuildCommand(for: v.path)
                        markCopied(v.path)
                    } label: {
                        Label(copied == v.path ? "Kopiert!" : "Rebuild-Cmd",
                              systemImage: copied == v.path ? "checkmark" : "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func markCopied(_ id: String) {
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copied == id { copied = nil }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(MD4.Typo.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
