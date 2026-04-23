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
        if let stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            try inPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
            try inPipe.fileHandleForWriting.close()
        }

        try process.run()
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                let outData = (try? out.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? err.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: ShellResult(
                    status: proc.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                ))
            }
        }
    }
}
