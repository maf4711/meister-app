import SwiftUI
import MeradOSDesign3

struct ProcessRow: Identifiable, Hashable {
    let id: Int             // pid
    let user: String
    let cpuPercent: Double
    let memPercent: Double
    let rssBytes: Int64
    let command: String
    var name: String {
        let parts = command.split(separator: " ", maxSplits: 1)
        let exe = String(parts.first ?? Substring(command))
        return (exe as NSString).lastPathComponent
    }
}

actor ProcessReader {
    func read() async -> [ProcessRow] {
        let raw = run("/bin/ps", ["-axc", "-o", "pid=,user=,%cpu=,%mem=,rss=,comm="])
        // -axc → all processes including others, comm only (without args, more readable)
        let withArgs = run("/bin/ps", ["-ax", "-o", "pid=,command="])
        let argMap = parseArgs(withArgs)
        return parse(raw, argMap: argMap)
    }

    nonisolated func parse(_ raw: String, argMap: [Int: String] = [:]) -> [ProcessRow] {
        var out: [ProcessRow] = []
        for line in raw.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 6,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[2]),
                  let mem = Double(parts[3]),
                  let rss = Int64(parts[4]) else { continue }
            let command = parts[5..<parts.count].joined(separator: " ")
            let fullCommand = argMap[pid] ?? command
            out.append(ProcessRow(
                id: pid,
                user: parts[1],
                cpuPercent: cpu,
                memPercent: mem,
                rssBytes: rss * 1024,    // ps returns KB
                command: fullCommand
            ))
        }
        return out.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    nonisolated func parseArgs(_ raw: String) -> [Int: String] {
        var out: [Int: String] = [:]
        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = Int(trimmed[..<space]) else { continue }
            let cmd = String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            out[pid] = cmd
        }
        return out
    }

    func kill(pid: Int, signal: Int32 = SIGTERM) async -> Bool {
        Foundation.kill(pid_t(pid), signal) == 0
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
final class ProcessManagerModel: ObservableObject {
    @Published var rows: [ProcessRow] = []
    @Published var query: String = ""
    @Published var sort: Sort = .cpu
    @Published var isLoading = false
    @Published var actionStatus: String?
    private let reader = ProcessReader()
    private var refreshTask: Task<Void, Never>?

    enum Sort: String, CaseIterable, Identifiable {
        case cpu, mem, name, pid
        var id: String { rawValue }
        var label: String {
            switch self {
            case .cpu: return "CPU"
            case .mem: return "Memory"
            case .name: return "Name"
            case .pid: return "PID"
            }
        }
    }

    var filtered: [ProcessRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var data = rows
        switch sort {
        case .cpu: data.sort { $0.cpuPercent > $1.cpuPercent }
        case .mem: data.sort { $0.memPercent > $1.memPercent }
        case .name: data.sort { $0.name.lowercased() < $1.name.lowercased() }
        case .pid: data.sort { $0.id < $1.id }
        }
        if !q.isEmpty {
            data = data.filter { $0.name.lowercased().contains(q) || $0.command.lowercased().contains(q) }
        }
        return data
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                isLoading = true
                self.rows = await reader.read()
                isLoading = false
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func kill(pid: Int, force: Bool) async {
        let ok = await reader.kill(pid: pid, signal: force ? SIGKILL : SIGTERM)
        actionStatus = ok ? "PID \(pid) → \(force ? "SIGKILL" : "SIGTERM") sent" : "kill PID \(pid) failed (permission?)"
    }
}

struct ProcessManagerView: View {
    @StateObject private var model = ProcessManagerModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MD3.SemColor.divider)
            controls
            Divider().background(MD3.SemColor.divider)
            list
        }
        .background(MD3.SemColor.background)
        .onAppear { model.startAutoRefresh() }
        .onDisappear { model.stopAutoRefresh() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Process Manager")
                    .font(MD3.Typo.title2)
                    .foregroundStyle(MD3.SemColor.textPrimary)
                Text("ps -ax + Live-Refresh alle 3 Sekunden. Kill via SIGTERM (default) oder SIGKILL (force).")
                    .font(MD3.Typo.small)
                    .foregroundStyle(MD3.SemColor.textSecondary)
            }
            Spacer()
            if let status = model.actionStatus {
                Text(status)
                    .font(MD3.Typo.caption)
                    .foregroundStyle(status.contains("failed") ? MD3.SemColor.error : MD3.SemColor.success)
            }
        }
        .padding(20)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MD3.SemColor.textSecondary)
                TextField("Filter…", text: $model.query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(MD3.SemColor.surfaceRaised, in: Capsule())
            Picker("Sort", selection: $model.sort) {
                ForEach(ProcessManagerModel.Sort.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            Spacer()
            Text("\(model.filtered.count) Prozesse")
                .font(MD3.Typo.caption)
                .foregroundStyle(MD3.SemColor.textSecondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var list: some View {
        List(model.filtered) { p in
            HStack(spacing: 8) {
                Text("\(p.id)")
                    .font(MD3.Typo.tabular(MD3.Typo.caption))
                    .foregroundStyle(MD3.SemColor.textSecondary)
                    .frame(width: 60, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name)
                        .font(MD3.Typo.body)
                        .foregroundStyle(MD3.SemColor.textPrimary)
                        .lineLimit(1)
                    Text(p.command)
                        .font(MD3.Typo.caption)
                        .foregroundStyle(MD3.SemColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                metric(String(format: "%.1f%%", p.cpuPercent), MD3.SemColor.warning, width: 60)
                metric(p.rssBytes.humanBytes, MD3.SemColor.brandPrimary, width: 80)
                Text(p.user)
                    .font(MD3.Typo.caption)
                    .foregroundStyle(MD3.SemColor.textSecondary)
                    .frame(width: 80, alignment: .leading)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await model.kill(pid: p.id, force: true) }
                } label: { Label("Kill -9", systemImage: "xmark.octagon") }
                Button {
                    Task { await model.kill(pid: p.id, force: false) }
                } label: { Label("Quit", systemImage: "stop.circle") }
                .tint(MD3.SemColor.warning)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func metric(_ text: String, _ color: Color, width: CGFloat) -> some View {
        Text(text)
            .font(MD3.Typo.tabular(MD3.Typo.caption))
            .foregroundStyle(color)
            .frame(width: width, alignment: .trailing)
    }
}
