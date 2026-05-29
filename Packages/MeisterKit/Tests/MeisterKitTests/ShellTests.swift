import XCTest
@testable import MeisterKit

final class ShellTests: XCTestCase {
    func testRunCompletesWhenStdoutExceedsPipeBuffer() async throws {
        let script = "yes 0123456789abcdef | head -n 20000"

        let result = try await withThrowingTaskGroup(of: ShellResult.self) { group in
            group.addTask {
                try await Shell.run(["/bin/sh", "-c", script])
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                throw TimeoutError()
            }

            let first = try await group.next()!
            group.cancelAll()
            return first
        }

        XCTAssertEqual(result.status, 0)
        XCTAssertGreaterThan(result.stdout.count, 200_000)
        XCTAssertEqual(result.stderr, "")
    }
}

private struct TimeoutError: Error {}
