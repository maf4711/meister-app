import Foundation
import CryptoKit

// Test-only instrumentation inserted immediately after real stream reads.
// Benchmarks compile the unchanged production source without these probes.
enum ReadProbe {
    private static let lock = NSLock()
    private static var baselineBytes = 0
    private static var candidateBytes = 0
    private static var cancellation: (threshold: Int, action: () -> Void)?

    static func record(_ count: Int, baseline: Bool) {
        guard count > 0 else { return }
        lock.lock()
        if baseline { baselineBytes += count } else { candidateBytes += count }
        if !baseline, let pending = cancellation, candidateBytes >= pending.threshold {
            cancellation = nil
            // Serialize cancellation with recorded reads so another worker cannot
            // race ahead while the callback thread is waiting to be scheduled.
            pending.action()
        }
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        baselineBytes = 0
        candidateBytes = 0
        cancellation = nil
    }

    static func cancelAfter(_ bytes: Int, action: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        cancellation = (bytes, action)
    }

    static var totals: (baseline: Int, candidate: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (baselineBytes, candidateBytes)
    }
}

@main struct DuplicatePerformanceChecks {
    static let fm = FileManager.default

    static func temporaryDirectory() throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func signature(_ hash: String, _ bytes: Int64, _ files: [URL]) -> String {
        "\(hash):\(bytes):" + files.map(\.lastPathComponent).sorted().joined(separator: ",")
    }

    static func equivalent(_ roots: [URL], minSize: Int64 = 0) async -> [DuplicateGroup] {
        let before = await ReferenceDuplicateFinder().find(in: roots, minSize: minSize)
        let after = await DuplicateFinder().find(in: roots, minSize: minSize)
        precondition(before.map { signature($0.hash, $0.bytes, $0.files) }.sorted() ==
                     after.map { signature($0.hash, $0.bytes, $0.files) }.sorted(), "Duplicate membership changed")
        precondition(before.map(\.wastedBytes).sorted() == after.map(\.wastedBytes).sorted())
        return after
    }

    static func boundaryChecks() async throws {
        for size in [0, 1, 65_535, 65_536, 65_537, 262_163] {
            let root = try temporaryDirectory()
            defer { try? fm.removeItem(at: root) }
            let data = Data(repeating: 23, count: size)
            try data.write(to: root.appendingPathComponent("a"))
            try data.write(to: root.appendingPathComponent("b"))
            if size > 0 {
                var different = data
                different[size - 1] = 24
                try different.write(to: root.appendingPathComponent("different-tail"))
            }
            ReadProbe.reset()
            let groups = await equivalent([root])
            precondition(groups.count == 1 && groups[0].files.count == 2)
            let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            precondition(groups[0].hash == expected, "A prefix digest escaped as a duplicate hash")
            if size <= 65_536 {
                precondition(ReadProbe.totals.baseline == ReadProbe.totals.candidate,
                             "Small files should not be read twice")
            }
        }
    }

    static func readReductionChecks() async throws {
        let root = try temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let size = 2 * 1024 * 1024
        for index in 0..<8 {
            try Data(repeating: UInt8(index), count: size).write(to: root.appendingPathComponent("file-\(index)"))
        }
        ReadProbe.reset()
        let distinct = await equivalent([root])
        precondition(distinct.isEmpty)
        precondition(ReadProbe.totals.baseline == 8 * size)
        precondition(ReadProbe.totals.candidate == 8 * 65_536,
                     "Distinct prefixes must avoid reading the rest of each file")

        try Data(repeating: 0, count: size).write(to: root.appendingPathComponent("copy"))
        ReadProbe.reset()
        let mixed = await equivalent([root])
        precondition(mixed.count == 1 && mixed[0].files.count == 2)
        precondition(ReadProbe.totals.baseline == 9 * size)
        precondition(ReadProbe.totals.candidate == 9 * 65_536 + 2 * size,
                     "Only a shared prefix should trigger full reads")

        let finder = DuplicateFinder()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await finder.find(in: [root], minSize: 0)
        }
        ReadProbe.reset()
        let cancelledResult = await cancelled.value
        precondition(cancelledResult.isEmpty && ReadProbe.totals.candidate == 0)
        precondition(DuplicateFinder.sha256(of: root.appendingPathComponent("missing")) == nil)

        // Cancel the parent deterministically from a real read, first during
        // prefix hashing and then during full hashing of the matching pair.
        for threshold in [1, 9 * 65_536 + 1] {
            let ready = DispatchSemaphore(value: 0)
            let running = Task.detached {
                ready.wait()
                return await DuplicateFinder().find(in: [root], minSize: 0)
            }
            ReadProbe.reset()
            ReadProbe.cancelAfter(threshold) { running.cancel() }
            ready.signal()
            let result = await running.value
            precondition(result.isEmpty, "A cancelled scan returned partial duplicate groups")
            let limit = threshold == 1 ? 4 * 65_536 : 9 * 65_536 + 4 * 262_144
            precondition(ReadProbe.totals.candidate <= limit, "Hashing continued after cancellation")
        }
    }

    static func mixedChecks() async throws {
        let root = try temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        // Repeated prefixes, true duplicates, and different suffixes after the sample.
        for index in 0..<48 {
            let family = index % 12
            var data = Data(repeating: UInt8(family % 3), count: 80_000 + family % 2)
            data[70_000] = UInt8(family)
            try data.write(to: root.appendingPathComponent("file-\(index)"))
        }
        let groups = await equivalent([root, root, root.appendingPathComponent("file-0")])
        precondition(groups.count == 12 && groups.allSatisfy { $0.files.count == 4 })
    }

    static func measure(_ operation: () async -> Void) async -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        await operation()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    static func benchmark() async throws {
        let size = 8 * 1024 * 1024
        for workload in ["distinct-prefix", "mixed-duplicates", "common-prefix", "all-duplicates"] {
            let root = try temporaryDirectory()
            defer { try? fm.removeItem(at: root) }
            for index in 0..<16 {
                var data = Data(repeating: workload == "all-duplicates" ? 0 : UInt8(index), count: size)
                if workload == "mixed-duplicates", index < 4 { data = Data(repeating: 0, count: size) }
                if workload == "common-prefix" { data.replaceSubrange(0..<65_536, with: repeatElement(UInt8(0), count: 65_536)) }
                try data.write(to: root.appendingPathComponent("file-\(index)"))
            }
            let expected = await equivalent([root])
            var baseline: [Double] = [], candidate: [Double] = []
            for iteration in 0..<5 {
                let runBaseline = {
                    let groups = await ReferenceDuplicateFinder().find(in: [root], minSize: 0)
                    precondition(groups.map(\.hash).sorted() == expected.map(\.hash).sorted())
                }
                let runCandidate = {
                    let groups = await DuplicateFinder().find(in: [root], minSize: 0)
                    precondition(groups.map(\.hash).sorted() == expected.map(\.hash).sorted())
                }
                if iteration % 2 == 0 {
                    baseline.append(await measure(runBaseline))
                    candidate.append(await measure(runCandidate))
                } else {
                    candidate.append(await measure(runCandidate))
                    baseline.append(await measure(runBaseline))
                }
            }
            let before = baseline.sorted()[2], after = candidate.sorted()[2]
            print("\(workload): baseline_ms=\(before) candidate_ms=\(after) speedup=\(before / after)")
            fflush(stdout)
        }
    }

    static func main() async throws {
        if CommandLine.arguments.contains("--benchmark") { try await benchmark() }
        else {
            try await boundaryChecks()
            try await readReductionChecks()
            try await mixedChecks()
            print("Duplicate scanner checks passed: boundaries, full-hash safety, bytes read, cancellation, membership")
        }
    }
}
