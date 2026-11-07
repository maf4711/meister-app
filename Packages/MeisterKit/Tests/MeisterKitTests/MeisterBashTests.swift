#if os(macOS)
import XCTest
@testable import MeisterKit

final class MeisterBashTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func script(_ name: String, executable: Bool = true) throws -> String {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/sh\nprintf '%s\\n' \"$@\"\nprintf 'diagnostic' >&2\nexit 7\n"
            .write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o700 : 0o600], ofItemAtPath: url.path)
        return url.path
    }

    func testDefaultOrderPrefersBothAIInstallationsBeforeFallbacks() {
        XCTAssertEqual(MeisterBash.defaultCandidatePaths, [
            "/opt/homebrew/bin/MeisterAI", "/usr/local/bin/MeisterAI",
            "/opt/homebrew/bin/meister", "/usr/local/bin/meister"
        ])
    }

    func testFirstExecutableWins() throws {
        let ai = try script("MeisterAI")
        let fallback = try script("meister")
        let backend = MeisterBash(candidatePaths: [ai, fallback])
        guard case .installed(let url) = backend.resolve() else { return XCTFail("missing") }
        XCTAssertEqual(url.path, ai)
        XCTAssertEqual(backend.executableName, "MeisterAI")
    }

    func testFallbackSkipsMissingAndNonExecutableCandidates() throws {
        let ai = try script("MeisterAI", executable: false)
        let fallback = try script("meister")
        let backend = MeisterBash(candidatePaths: [directory.appendingPathComponent("missing").path, ai, fallback])
        guard case .installed(let url) = backend.resolve() else { return XCTFail("missing") }
        XCTAssertEqual(url.path, fallback)
        XCTAssertEqual(backend.executableName, "meister")
    }

    func testMissingBackendThrowsInsteadOfExecuting() async throws {
        let backend = MeisterBash(candidatePaths: [])
        guard case .missing = backend.resolve() else { return XCTFail("unexpected executable") }
        do {
            _ = try await backend.run(["doctor"])
            XCTFail("Expected notInstalled")
        } catch MeisterBashError.notInstalled { }
    }

    func testArgumentsAndExitStatusRemainUnchanged() async throws {
        let backend = MeisterBash(candidatePaths: [try script("MeisterAI")])
        let result = try await backend.run(["doctor", "argument with spaces", "$(literal)"])
        XCTAssertEqual(result.stdout, "doctor\nargument with spaces\n$(literal)\n")
        XCTAssertEqual(result.stderr, "diagnostic")
        XCTAssertEqual(result.status, 7)
        XCTAssertFalse(result.ok)
    }

    func testHealRemainsDryRunByDefault() async throws {
        let backend = MeisterBash(candidatePaths: [try script("MeisterAI")])
        let result = try await backend.heal()
        XCTAssertEqual(result.stdout, "heal\n--dry-run\n")
    }
}
#endif
