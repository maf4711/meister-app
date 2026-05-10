import Foundation
import Network

/// Full Ookla-style speedtest: parallel TCP pings for latency + jitter,
/// a 10 MB Cloudflare download, and a 5 MB upload. Results are stored
/// in UserDefaults so the Diagnostics tab can draw a history graph.
actor SpeedtestPro {
    struct Result: Codable, Identifiable, Hashable {
        let id: UUID
        let timestamp: Date
        let pingMs: Double
        let jitterMs: Double
        let downloadMbps: Double
        let uploadMbps: Double
    }

    static func loadHistory() -> [Result] {
        guard let data = UserDefaults.standard.data(forKey: "speedtestHistory") else { return [] }
        let decoded = (try? JSONDecoder().decode([Result].self, from: data)) ?? []
        // Tom on Build 30 still hit Speedtest crashes — even after ResumeBox.
        // Likely culprit: old history rows from pre-fix builds contain
        // .infinity or .nan in downloadMbps/uploadMbps because the
        // measure functions used to divide by a sub-millisecond elapsed.
        // Charts.framework crashes when LineMark gets a non-finite Y.
        // Drop any row that has a non-finite component before returning.
        return decoded.filter { row in
            row.pingMs.isFinite && row.jitterMs.isFinite
                && row.downloadMbps.isFinite && row.uploadMbps.isFinite
        }
    }

    static func save(_ result: Result) {
        var history = loadHistory()
        // sanitize the new row too — defensive belt+braces, in case a future
        // measurement bypasses the divide-by-zero guard.
        let safe = Result(
            id: result.id,
            timestamp: result.timestamp,
            pingMs: result.pingMs.isFinite ? result.pingMs : 0,
            jitterMs: result.jitterMs.isFinite ? result.jitterMs : 0,
            downloadMbps: result.downloadMbps.isFinite ? result.downloadMbps : 0,
            uploadMbps: result.uploadMbps.isFinite ? result.uploadMbps : 0
        )
        history.append(safe)
        if history.count > 60 { history.removeFirst(history.count - 60) }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "speedtestHistory")
        }
    }

    /// Run the full suite. Designed to be called with progress callbacks so the
    /// view can animate a rolling chart. Download size 10 MB, upload 5 MB.
    func run(progress: @Sendable @escaping (String, Double) -> Void = { _, _ in }) async -> Result {
        progress("Measuring latency", 0)
        let pings = await measurePings(host: "1.1.1.1", samples: 5)
        let avg = pings.reduce(0, +) / Double(pings.count)
        let jitter = pings.map { abs($0 - avg) }.reduce(0, +) / Double(pings.count)

        progress("Downloading", 0.3)
        let download = await measureDownload(byteCount: 10_485_760)

        progress("Uploading", 0.7)
        let upload = await measureUpload(byteCount: 5_242_880)

        progress("Complete", 1)
        let result = Result(
            id: UUID(),
            timestamp: .now,
            pingMs: avg,
            jitterMs: jitter,
            downloadMbps: download,
            uploadMbps: upload
        )
        Self.save(result)
        return result
    }

    private func measurePings(host: String, samples: Int) async -> [Double] {
        var results: [Double] = []
        for _ in 0..<samples {
            let value = await tcpPing(host: host)
            // Drop failed pings (-1 sentinel) so jitter/avg don't get poisoned.
            if value >= 0 { results.append(value) }
        }
        // Guard against the all-failed case — return at least one row so the
        // upstream avg/jitter math doesn't divide by zero.
        return results.isEmpty ? [0] : results
    }

    /// Returns latency in ms, or -1 if the connection failed / timed out.
    ///
    /// Round 3 fix: Tom kept hitting the crash on Build 27/28/29 even
    /// after my "var resumed + NSLock" patch. Under Swift 6 strict
    /// concurrency, capturing a `var` in @Sendable closures dispatched
    /// to multiple queues isn't reliable — the value isn't shared with
    /// proper memory ordering across the NWConnection internal queue
    /// and the failsafe timer queue. So .ready and the subsequent
    /// .cancelled (triggered by our own cancel() call) could BOTH see
    /// `resumed = false`, and both call continuation.resume() →
    /// SWIFT TASK CONTINUATION MISUSE → crash.
    ///
    /// A heap-allocated class instance is the iron-clad fix: the
    /// reference is genuinely shared, NSLock provides the memory
    /// ordering, and resume() is guaranteed to fire exactly once.
    private final class ResumeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        private let continuation: CheckedContinuation<Double, Never>
        init(_ continuation: CheckedContinuation<Double, Never>) {
            self.continuation = continuation
        }
        func resume(_ value: Double) {
            lock.lock()
            let alreadyResumed = resumed
            resumed = true
            lock.unlock()
            guard !alreadyResumed else { return }
            continuation.resume(returning: value)
        }
    }

    private func tcpPing(host: String) async -> Double {
        await withCheckedContinuation { (continuation: CheckedContinuation<Double, Never>) in
            let start = Date()
            let connection = NWConnection(host: .init(host), port: 443, using: .tcp)
            let box = ResumeBox(continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Date().timeIntervalSince(start) * 1000
                    box.resume(elapsed)
                    connection.cancel()
                case .failed, .cancelled:
                    box.resume(-1)
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global())

            // Failsafe: if neither .ready nor .failed fires within 3 s, give up.
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                box.resume(-1)
                connection.cancel()
            }
        }
    }

    private func measureDownload(byteCount: Int) async -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(byteCount)") else { return 0 }
        let start = Date()
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let seconds = Date().timeIntervalSince(start)
            // Guard against impossibly fast responses (cached, redirected) — a
            // sub-millisecond seconds value would yield .infinity Mbps and
            // JSONEncoder would later choke on the saved history.
            guard seconds > 0.001 else { return 0 }
            return (Double(data.count) * 8.0 / 1_000_000) / seconds
        } catch {
            return 0
        }
    }

    private func measureUpload(byteCount: Int) async -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else { return 0 }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let payload = Data(count: byteCount)
        let start = Date()
        do {
            let (_, _) = try await URLSession.shared.upload(for: request, from: payload)
            let seconds = Date().timeIntervalSince(start)
            guard seconds > 0.001 else { return 0 }
            return (Double(byteCount) * 8.0 / 1_000_000) / seconds
        } catch {
            return 0
        }
    }
}
