#if os(macOS)
import Foundation

/// Thin Swift wrapper around the bash-based `meister` CLI from the
/// `maf4711/homebrew-meister` tap. Shells out to the installed binary
/// instead of reimplementing its logic, so the macOS GUI stays in sync
/// with whatever `brew upgrade meister` ships.
///
/// The wrapper is purely macOS; iOS uses native Swift modules directly.
public struct MeisterBash: Sendable {
    public enum Resolution: Sendable {
        case installed(URL)
        case missing
    }

    public struct RunResult: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String
        public var ok: Bool { status == 0 }
    }

    public static let shared = MeisterBash()

    /// Preferred install locations, in priority order.
    private static let candidatePaths: [String] = [
        "/opt/homebrew/bin/meister",
        "/usr/local/bin/meister",
    ]

    public func resolve() -> Resolution {
        for path in Self.candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return .installed(URL(fileURLWithPath: path))
            }
        }
        return .missing
    }

    /// Run `meister <subcommand...>`, capture stdout/stderr, return structured result.
    public func run(_ args: [String], stdin: String? = nil) async throws -> RunResult {
        guard case .installed(let url) = resolve() else {
            throw MeisterBashError.notInstalled
        }
        let argv = [url.path] + args
        let shell = try await Shell.run(argv, stdin: stdin)
        return RunResult(status: shell.status, stdout: shell.stdout, stderr: shell.stderr)
    }

    // MARK: - Typed module wrappers (thin; expand as needed)

    public func health() async throws -> RunResult {
        try await run(["-H"])
    }

    public func maintenanceDryRun() async throws -> RunResult {
        try await run(["-n", "-a"])
    }

    public func disk(_ path: String = "~") async throws -> RunResult {
        try await run(["disk", (path as NSString).expandingTildeInPath])
    }

    public func battery() async throws -> RunResult {
        try await run(["battery"])
    }

    public func wifi() async throws -> RunResult {
        try await run(["wifi"])
    }

    public func ports() async throws -> RunResult {
        try await run(["ports"])
    }

    public func dns() async throws -> RunResult {
        try await run(["dns"])
    }

    public func certs(_ host: String) async throws -> RunResult {
        try await run(["certs", host])
    }

    public func thermal() async throws -> RunResult {
        try await run(["thermal", "1"]) // one snapshot
    }

    public func heal(dryRun: Bool = true) async throws -> RunResult {
        try await run(dryRun ? ["heal", "--dry-run"] : ["heal"])
    }
}

public enum MeisterBashError: Error, LocalizedError {
    case notInstalled

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The `meister` CLI is not installed. Run `brew tap maf4711/meister && brew install meister` to enable the GUI modules that depend on it."
        }
    }
}
#endif
