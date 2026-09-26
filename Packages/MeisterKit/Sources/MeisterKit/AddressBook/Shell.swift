import Foundation
import Darwin

public struct ShellResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public var terminationSignal: Int32? = nil
}

public enum ShellError: Error, LocalizedError, Equatable {
    case invalidArguments, system(Int32), timedOut, outputLimit
    public var errorDescription: String? {
        switch self {
        case .invalidArguments: return "Ungültiger Programmaufruf."
        case .system(let code): return "Programmaufruf fehlgeschlagen (Systemfehler \(code))."
        case .timedOut: return "Zeitlimit überschritten."
        case .outputLimit: return "Ausgabegrenze überschritten; Ergebnis unvollständig."
        }
    }
}

public enum Shell {
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        func cancel() { lock.lock(); stopped = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    }

    public static func run(_ argv: [String], stdin: String? = nil,
                           timeout: TimeInterval = 300, maximumOutputBytes: Int = 16 * 1024 * 1024,
                           onOutput: (@Sendable (ShellResult) -> Void)? = nil) async throws -> ShellResult {
        let cancellation = Cancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        continuation.resume(returning: try runSynchronously(argv, stdin: stdin,
                            timeout: timeout, maximumOutputBytes: maximumOutputBytes,
                            isCancelled: { cancellation.isCancelled }, onOutput: onOutput))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    /// Each invocation owns a new process group. Cancellation and deadlines terminate that group.
    /// Children that deliberately create another session/group are outside this ownership boundary.
    public static func runSynchronously(_ argv: [String], stdin: String? = nil,
                                        timeout: TimeInterval = 300, maximumOutputBytes: Int = 16 * 1024 * 1024,
                                        isCancelled: @escaping @Sendable () -> Bool = { false },
                                        onOutput: (@Sendable (ShellResult) -> Void)? = nil) throws -> ShellResult {
        guard !argv.isEmpty, argv[0].hasPrefix("/"), argv.allSatisfy({ !$0.contains("\0") }),
              timeout.isFinite, timeout > 0, maximumOutputBytes > 0 else { throw ShellError.invalidArguments }
        if isCancelled() { throw CancellationError() }
        var descriptors: [Int32] = []
        func makePipe() throws -> [Int32] {
            var pair: [Int32] = [0, 0]
            guard pipe(&pair) == 0 else { throw ShellError.system(errno) }
            descriptors += pair
            for fd in pair { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
            return pair
        }
        func closeFD(_ fd: Int32) {
            if let index = descriptors.firstIndex(of: fd) { close(fd); descriptors.remove(at: index) }
        }
        defer { for fd in descriptors { close(fd) } }
        let out = try makePipe(), err = try makePipe(), input = try makePipe()
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        func check(_ code: Int32) throws { if code != 0 { throw ShellError.system(code) } }
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        for (source, target) in [(input[0], STDIN_FILENO), (out[1], STDOUT_FILENO), (err[1], STDERR_FILENO)] {
            try check(posix_spawn_file_actions_adddup2(&actions, source, target))
        }
        for fd in descriptors { try check(posix_spawn_file_actions_addclose(&actions, fd)) }
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let args = argv.map { strdup($0) } + [nil]
        let env = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for pointer in args + env { free(pointer) } }
        var pid: pid_t = 0
        if isCancelled() { throw CancellationError() }
        try check(posix_spawn(&pid, argv[0], &actions, &attributes, args, env))
        closeFD(input[0]); closeFD(out[1]); closeFD(err[1])
        for fd in [input[1], out[0], err[0]] { _ = fcntl(fd, F_SETFL, O_NONBLOCK) }
        _ = fcntl(input[1], F_SETNOSIGPIPE, 1)
        let inputData = Data((stdin ?? "").utf8)
        var inputOffset = 0
        var stdout = Data(), stderr = Data()
        var outputOpen = true, errorOpen = true
        var status: Int32 = 0
        var reaped = false
        let start = ProcessInfo.processInfo.systemUptime
        var stoppedAt: TimeInterval?
        var failure: Error?
        var lastUpdate = start
        var changed = false
        var killed = false
        func snapshot() -> ShellResult {
            ShellResult(status: (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f), stdout: String(decoding: stdout, as: UTF8.self), stderr: String(decoding: stderr, as: UTF8.self))
        }
        func drain(_ fd: Int32, _ data: inout Data, _ open: inout Bool) {
            guard open else { return }
            var buffer = [UInt8](repeating: 0, count: 65536)
            // Bounded work per iteration so a noisy child cannot starve cancellation/deadlines.
            for _ in 0..<8 {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count > 0 {
                    let remaining = max(0, maximumOutputBytes - data.count)
                    data.append(contentsOf: buffer.prefix(min(count, remaining)))
                    changed = true
                    if count > remaining { failure = failure ?? ShellError.outputLimit; return }
                } else if count == 0 { open = false; closeFD(fd); return }
                else if errno == EAGAIN || errno == EINTR { return }
                else { failure = failure ?? ShellError.system(errno); open = false; closeFD(fd); return }
            }
        }
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            if isCancelled() { failure = failure ?? CancellationError() }
            if now - start >= timeout { failure = failure ?? ShellError.timedOut }
            if failure != nil && stoppedAt == nil {
                stoppedAt = now
                Darwin.kill(-pid, SIGTERM)
                closeFD(input[1])
            }
            if let stoppedAt, now - stoppedAt >= 0.25, !killed {
                Darwin.kill(-pid, SIGKILL)
                killed = true
            }
            if descriptors.contains(input[1]) {
                if inputOffset == inputData.count { closeFD(input[1]) }
                else {
                    let count = inputData.withUnsafeBytes { bytes in
                        Darwin.write(input[1], bytes.baseAddress!.advanced(by: inputOffset), min(65536, inputData.count - inputOffset))
                    }
                    if count > 0 { inputOffset += count }
                    else if count < 0 && errno != EAGAIN && errno != EINTR {
                        let writeError = errno
                        closeFD(input[1])
                        // A program may intentionally finish without consuming all input.
                        if writeError != EPIPE { failure = failure ?? ShellError.system(writeError) }
                    }
                }
            }
            drain(out[0], &stdout, &outputOpen)
            drain(err[0], &stderr, &errorOpen)
            if !reaped {
                let result = waitpid(pid, &status, WNOHANG)
                if result == pid { reaped = true }
                else if result < 0 && errno != EINTR { failure = failure ?? ShellError.system(errno); reaped = true }
            }
            if changed && now - lastUpdate >= 0.1 {
                onOutput?(snapshot()); changed = false; lastUpdate = now
            }
            if reaped && !outputOpen && !errorOpen && (stoppedAt == nil || killed) { break }
            // Escaped descendants can retain descriptors; do not let them hold this caller forever.
            if let stoppedAt, now - stoppedAt >= 1, reaped { break }
            usleep(10_000)
        }
        onOutput?(snapshot())
        if let failure { throw failure }
        let signal = status & 0x7f
        var result = snapshot()
        result.terminationSignal = signal == 0 ? nil : signal
        return result
    }
}
