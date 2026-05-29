import Foundation

public struct ShellResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public enum Shell {
    public static func run(_ argv: [String], stdin: String? = nil) async throws -> ShellResult {
        precondition(!argv.isEmpty, "argv must not be empty")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let input: Pipe?
        if stdin != nil {
            let inPipe = Pipe()
            process.standardInput = inPipe
            input = inPipe
        } else {
            input = nil
        }

        try process.run()

        let stdinTask = Task.detached {
            if let stdin, let input {
                try input.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
            }
            try input?.fileHandleForWriting.close()
        }
        let stdoutTask = Task.detached {
            (try? out.fileHandleForReading.readToEnd()) ?? Data()
        }
        let stderrTask = Task.detached {
            (try? err.fileHandleForReading.readToEnd()) ?? Data()
        }
        let statusTask = Task.detached {
            process.waitUntilExit()
            return process.terminationStatus
        }

        try await stdinTask.value
        let status = await statusTask.value
        let outData = await stdoutTask.value
        let errData = await stderrTask.value

        return ShellResult(
            status: status,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
