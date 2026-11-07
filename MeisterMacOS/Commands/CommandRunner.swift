import Foundation
import Darwin

/// Time-limited native diagnostic commands with output capture.
/// Capture uses an unlinked private file so large output cannot fill a pipe buffer.
enum CommandRunner {
    struct Result: Sendable {
        let status: Int32
        let output: String
        var failureKind: DiagnosticIssue.Kind? = nil
        var succeeded: Bool { status == 0 && failureKind == nil }

        func issue(source: String) -> DiagnosticIssue? {
            if let failureKind { return .init(kind: failureKind, source: source) }
            guard status != 0 else { return nil }
            let lower = output.lowercased()
            let denied = lower.contains("permission denied") || lower.contains("operation not permitted")
            return .init(kind: denied ? .permissionDenied : .executionFailed, source: source)
        }
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) -> Result {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return Result(status: 127, output: "", failureKind: .missingTool)
        }
        guard timeout.isFinite, timeout > 0 else {
            return Result(status: 124, output: "", failureKind: .timedOut)
        }
        var template = Array((NSTemporaryDirectory() + "meister-command-XXXXXX").utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else {
            return Result(status: 125, output: "", failureKind: .executionFailed)
        }
        unlink(template)
        let capture = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? capture.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = capture
        process.standardError = capture
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch {
            return Result(status: 126, output: "", failureKind: .executionFailed)
        }
        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
        }
        do {
            try capture.seek(toOffset: 0)
            let data = try capture.readToEnd() ?? Data()
            return Result(status: timedOut ? 124 : process.terminationStatus,
                          output: String(decoding: data, as: UTF8.self),
                          failureKind: timedOut ? .timedOut : nil)
        } catch {
            return Result(status: 125, output: "", failureKind: .executionFailed)
        }
    }
}
