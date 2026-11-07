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

extension ShellTests {
    func testStdinAndBothOutputStreamsBeyondPipeCapacity() async throws {
        let input = String(repeating: "Grüße 🛠\n", count: 20000)
        let result = try await Shell.run(["/bin/sh", "-c", "cat; printf 'diagnostic' >&2"], stdin: input)
        XCTAssertEqual(result.stdout, input)
        XCTAssertEqual(result.stderr, "diagnostic")
        XCTAssertEqual(result.status, 0)
    }

    func testPreCancelledInvocationDoesNotLaunch() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        XCTAssertThrowsError(try Shell.runSynchronously(["/usr/bin/touch", marker.path], isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testLargeStderrDoesNotBlockStdout() async throws {
        let result = try await Shell.run(["/bin/sh", "-c", "yes error | head -n 20000 >&2; echo finished"], timeout: 2)
        XCTAssertEqual(result.stdout, "finished\n")
        XCTAssertGreaterThan(result.stderr.count, 65536)
        XCTAssertEqual(result.status, 0)
    }

    func testNoInputClosesStdin() async throws {
        let result = try await Shell.run(["/bin/cat"], timeout: 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.status, 0)
    }

    func testTimeoutKillsGroupEvenAfterLeaderExits() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        do {
            _ = try await Shell.run(["/bin/sh", "-c", "(trap '' TERM; sleep 1; touch \"$1\") & exit 0", "test", marker.path], timeout: 0.1)
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? ShellError, .timedOut) }
        try await Task.sleep(for: .seconds(1.1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testCancellationStopsChildren() async throws {
        let started = expectation(description: "stream arrived before completion")
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let once = Once()
        let task = Task {
            try await Shell.run(["/bin/sh", "-c", "(sleep 1; touch \"$1\") & echo ready; wait", "test", marker.path], onOutput: { result in
                if result.stdout.contains("ready") { once.perform { started.fulfill() } }
            })
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await Task.sleep(for: .seconds(1.1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testOutputLimitTerminatesNoisyProcess() async {
        do {
            _ = try await Shell.run(["/usr/bin/yes"], timeout: 2, maximumOutputBytes: 1024)
            XCTFail("Expected output limit")
        } catch { XCTAssertEqual(error as? ShellError, .outputLimit) }
    }

    func testInvalidAndMissingCommandsThrow() async {
        for argv in [[], ["relative"], ["/bin/echo", "bad\0argument"]] {
            do { _ = try await Shell.run(argv); XCTFail("Expected validation error") }
            catch { XCTAssertEqual(error as? ShellError, .invalidArguments) }
        }
        do { _ = try await Shell.run(["/nonexistent/meister"]); XCTFail("Expected launch failure") }
        catch { XCTAssertEqual(error as? ShellError, .system(ENOENT)) }
    }

    func testExitCodeAndSignalAreDistinct() async throws {
        let exit = try await Shell.run(["/bin/sh", "-c", "exit 137"])
        XCTAssertEqual(exit.status, 137)
        XCTAssertNil(exit.terminationSignal)
        let signal = try await Shell.run(["/bin/sh", "-c", "kill -KILL $$"])
        XCTAssertEqual(signal.status, 137)
        XCTAssertEqual(signal.terminationSignal, SIGKILL)
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func perform(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
