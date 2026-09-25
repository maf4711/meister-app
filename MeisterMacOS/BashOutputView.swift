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
    @State private var showConfirm: Bool = false
    @State private var runTask: Task<Void, Never>?
    @State private var runID = UUID()

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
        .task(id: module.id) {
            bashInstalled = isBashInstalled()
            output = ""
            errorText = ""
            exitStatus = nil
            if bashInstalled && !module.runsLive && !module.takesHostInput && !module.destructive {
                startRun()
            }
        }
        .onDisappear { runTask?.cancel() }
        .alert("Run \(module.title)?",
               isPresented: $showConfirm,
               actions: {
                   Button("Cancel", role: .cancel) {}
                   Button("Proceed", role: .destructive) { startRun() }
               },
               message: {
                   Text("This runs `\(MeisterBash.shared.executableName) \(module.command.joined(separator: " "))` with destructive intent on your system.")
               })
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(module.title).font(.title2).bold()
                Text("\(MeisterBash.shared.executableName) \(module.command.joined(separator: " "))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if module.takesHostInput {
                TextField("host (e.g. apple.com)", text: $hostInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            if isRunning {
                Button("Abbrechen", role: .cancel) { runTask?.cancel() }
            }
            Button {
                if module.destructive {
                    showConfirm = true
                } else {
                    startRun()
                }
            } label: {
                Label(isRunning ? "Running…" : (module.destructive ? "Run (destructive)" : "Run"),
                      systemImage: module.destructive ? "exclamationmark.triangle.fill" : "play.fill")
            }
            .tint(module.destructive ? .orange : .accentColor)
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
            Text("MeisterAI not found").font(.title2).bold()
            Text("The macOS GUI uses the `MeisterAI` CLI (with `meister` fallback) as its backend.\nInstall it first:")
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

    @MainActor
    private func startRun() {
        guard !isRunning else { return }
        let id = UUID()
        runID = id
        isRunning = true
        runTask = Task { await run(id: id) }
    }

    @MainActor
    private func run(id: UUID) async {
        isRunning = true
        output = ""
        errorText = ""
        exitStatus = nil
        defer { isRunning = false }

        var args = module.command
        if module.takesHostInput { args.append(hostInput) }
        if module.id == "disk" { args.append(NSHomeDirectory()) }

        do {
            let result = try await MeisterBash.shared.run(args, timeout: 300) { update in
                Task { @MainActor in
                    guard runID == id, isRunning else { return }
                    output = update.stdout
                    errorText = update.stderr
                }
            }
            output = result.stdout
            errorText = result.stderr
            exitStatus = result.status
        } catch is CancellationError {
            errorText += "\nAbgebrochen. Bereits ausgeführte Änderungen werden dadurch nicht rückgängig gemacht."
            exitStatus = -1
        } catch {
            errorText += "\n" + error.localizedDescription
            exitStatus = -1
        }
    }

    private func isBashInstalled() -> Bool {
        if case .installed = MeisterBash.shared.resolve() { return true }
        return false
    }
}
