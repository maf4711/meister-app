import SwiftUI
import AppKit
import MeradOSDesign4

struct AppSignature: Identifiable, Hashable {
    let id: String          // bundle path
    let name: String
    let url: URL
    let teamID: String?
    let authority: String?  // signing certificate authority
    let status: SignStatus

    enum SignStatus: Equatable, Hashable {
        case valid(String)
        case invalid(String)
        case unsigned
        case error(String)
    }
}

actor CodeSignatureReader {
    func read() async -> [AppSignature] {
        let appsDirs = ["/Applications", "/Applications/Utilities"]
        var out: [AppSignature] = []
        for dir in appsDirs {
            let url = URL(fileURLWithPath: dir)
            let entries = (try? FileManager.default.contentsOfDirectory(at: url,
                                                                         includingPropertiesForKeys: nil)) ?? []
            for app in entries where app.pathExtension == "app" {
                out.append(inspect(app))
            }
        }
        return out.sorted { $0.status.sortKey < $1.status.sortKey }
    }

    private nonisolated func inspect(_ url: URL) -> AppSignature {
        let name = url.deletingPathExtension().lastPathComponent

        // codesign --display --verbose gives authority + team
        let display = run("/usr/bin/codesign", ["--display", "--verbose", url.path])
        let verify  = run("/usr/bin/codesign", ["--verify", "--verbose", url.path])

        let team      = parseField("TeamIdentifier", from: display)
        let authority = parseField("Authority", from: display)

        let status: AppSignature.SignStatus
        if display.output.lowercased().contains("code object is not signed") ||
           display.output.lowercased().contains("unsatisfied entitlement") ||
           verify.output.lowercased().contains("is not signed") {
            status = .unsigned
        } else if verify.terminationStatus == 0 {
            status = .valid(authority ?? "Apple")
        } else {
            let msg = (verify.output).trimmingCharacters(in: .whitespacesAndNewlines)
            if msg.isEmpty {
                status = .invalid("Signature verification failed")
            } else {
                status = .invalid(msg)
            }
        }

        return AppSignature(
            id: url.path,
            name: name,
            url: url,
            teamID: team,
            authority: authority,
            status: status
        )
    }

    private nonisolated func parseField(_ key: String, from raw: (output: String, terminationStatus: Int32)) -> String? {
        for line in raw.output.split(separator: "\n") {
            if line.hasPrefix(key + "=") || line.contains(key + "=") {
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                return String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private nonisolated func run(_ tool: String, _ args: [String]) -> (output: String, terminationStatus: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run(); p.waitUntilExit() } catch { return ("", -1) }
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (out + err, p.terminationStatus)
    }
}

private extension AppSignature.SignStatus {
    var sortKey: Int {
        switch self {
        case .invalid: return 0
        case .unsigned: return 1
        case .error: return 2
        case .valid: return 3
        }
    }
}

@MainActor
final class CodeSignatureModel: ObservableObject {
    @Published var apps: [AppSignature] = []
    @Published var isLoading = false
    @Published var filter: FilterMode = .all
    private let reader = CodeSignatureReader()

    enum FilterMode: String, CaseIterable, Identifiable {
        case all, issues, valid
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "Alle"
            case .issues: return "Probleme"
            case .valid: return "Gültig"
            }
        }
    }

    var filtered: [AppSignature] {
        switch filter {
        case .all: return apps
        case .issues: return apps.filter { if case .valid = $0.status { return false }; return true }
        case .valid: return apps.filter { if case .valid = $0.status { return true }; return false }
        }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        self.apps = await reader.read()
    }
}

struct CodeSignatureView: View {
    @StateObject private var model = CodeSignatureModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD4.SemColor.divider)
            controls
            Divider().background(MD4.SemColor.divider)
            list
        }
        .background(MD4.SemColor.background)
        .task { if model.apps.isEmpty { await model.reload() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Code Signature")
                    .font(MD4.Typo.title2)
                    .foregroundStyle(MD4.SemColor.textPrimary)
                Text("codesign --verify für alle Apps in /Applications. Unsigned oder invalid zuerst.")
                    .font(MD4.Typo.small)
                    .foregroundStyle(MD4.SemColor.textSecondary)
            }
            Spacer()
            Button { Task { await model.reload() } } label: {
                Label(model.isLoading ? "Prüft…" : "Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
        .padding(20)
    }

    private var controls: some View {
        HStack {
            Picker("Filter", selection: $model.filter) {
                ForEach(CodeSignatureModel.FilterMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            Spacer()
            let issues = model.apps.filter { if case .valid = $0.status { return false }; return true }.count
            if issues > 0 {
                Text("\(issues) App\(issues == 1 ? "" : "s") mit Problemen")
                    .font(MD4.Typo.caption.bold())
                    .foregroundStyle(MD4.SemColor.warning)
            } else if !model.apps.isEmpty {
                Text("Alle \(model.apps.count) Apps gültig")
                    .font(MD4.Typo.caption)
                    .foregroundStyle(MD4.SemColor.success)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var list: some View {
        Group {
            if model.isLoading && model.apps.isEmpty {
                ProgressView("Prüfe \(model.apps.count) Apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.filtered) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .font(MD4.Typo.body)
                                .foregroundStyle(MD4.SemColor.textPrimary)
                            if let authority = app.authority {
                                Text(authority)
                                    .font(MD4.Typo.caption)
                                    .foregroundStyle(MD4.SemColor.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        statusBadge(app.status)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func statusBadge(_ s: AppSignature.SignStatus) -> some View {
        let (label, color, icon): (String, Color, String) = {
            switch s {
            case .valid:    return ("Gültig", MD4.SemColor.success, "checkmark.seal.fill")
            case .unsigned: return ("Unsigniert", MD4.SemColor.warning, "exclamationmark.triangle.fill")
            case .invalid: return ("Ungültig", MD4.SemColor.error, "xmark.seal.fill")
            case .error:    return ("Fehler", MD4.SemColor.textTertiary, "questionmark.circle")
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(MD4.Typo.caption.bold())
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
    }
}
