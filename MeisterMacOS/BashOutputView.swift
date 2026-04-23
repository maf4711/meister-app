import SwiftUI
import MeisterKit

struct BashOutputView: View {
    let module: BashModule
    @State private var output: String = ""
    @State private var errorText: String = ""
    @State private var exitStatus: Int32? = nil
    @State private var isRunning: Bool = false
    @State private var hostInput: String = ""
    @State private var bashInstalled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !bashInstalled {
                missingBashCLI
            } else {
                content
            }
        }
        .task {
            bashInstalled = isBashInstalled()
            if bashInstalled && !module.runsLive && !module.takesHostInput {
                await run()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(module.title).font(.title2).bold()
                Text("meister \(module.command.joined(separator: " "))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if module.takesHostInput {
                TextField("host (e.g. apple.com)", text: $hostInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            Button {
                Task { await run() }
            } label: {
                Label(isRunning ? "Running…" : "Run", systemImage: "play.fill")
            }
            .disabled(isRunning || (module.takesHostInput && hostInput.isEmpty))
            .keyboardShortcut("r")
        }
        .padding(20)
    }

    // MARK: - Output

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if isRunning {
                    ProgressView().controlSize(.small)
                }
                if !output.isEmpty {
                    Text(output)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if let status = exitStatus, status != 0 {
                    Text("Exit status: \(status)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if output.isEmpty && errorText.isEmpty && !isRunning && exitStatus == nil {
                    Text(module.runsLive ? "Press Run to execute this module." : "Waiting…")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private var missingBashCLI: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("bash-meister not found").font(.title2).bold()
            Text("The macOS GUI uses the bash-based `meister` CLI as its backend.\nInstall it first:")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("brew tap maf4711/meister\nbrew install meister")
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Execution

    private func run() async {
        isRunning = true
        output = ""
        errorText = ""
        exitStatus = nil
        defer { isRunning = false }

        var args = module.command
        if module.takesHostInput { args.append(hostInput) }
        if module.id == "disk" { args.append(NSHomeDirectory()) }

        do {
            let result = try await MeisterBash.shared.run(args)
            output = result.stdout
            errorText = result.stderr
            exitStatus = result.status
        } catch {
            errorText = error.localizedDescription
            exitStatus = -1
        }
    }

    private func isBashInstalled() -> Bool {
        if case .installed = MeisterBash.shared.resolve() { return true }
        return false
    }
}
