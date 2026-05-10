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
        return (try? JSONDecoder().decode([Result].self, from: data)) ?? []
    }

    static func save(_ result: Result) {
        var history = loadHistory()
        history.append(result)
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
    /// The previous implementation called `continuation.resume()` from both
    /// the `.ready` AND `.cancelled` branches — and `connection.cancel()`
    /// triggers `.cancelled` immediately after `.ready` — which fatal-errored
    /// the CheckedContinuation. This was Tom's "Speedtest stürzt immer noch
    /// ab" crash. Resume-once flag + 3-second timeout fixes both:
    /// - exactly one resume even on rapid state transitions
    /// - never hangs forever on a blocked port
    private func tcpPing(host: String) async -> Double {
        await withCheckedContinuation { (continuation: CheckedContinuation<Double, Never>) in
            let start = Date()
            let connection = NWConnection(host: .init(host), port: 443, using: .tcp)

            // Atomic resume guard. NWConnection state callbacks can fire from
            // multiple queues and may transition .ready → .cancelled almost
            // simultaneously when we call cancel(); we must only resume once.
            let lock = NSLock()
            var resumed = false
            let resume: (Double) -> Void = { value in
                lock.lock()
                let alreadyResumed = resumed
                resumed = true
                lock.unlock()
                guard !alreadyResumed else { return }
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Date().timeIntervalSince(start) * 1000
                    resume(elapsed)
                    connection.cancel()
                case .failed, .cancelled:
                    resume(-1)
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global())

            // Failsafe: if neither .ready nor .failed fires within 3 s, give up.
            // Without this the test could hang forever on a blocked port and
            // the CheckedContinuation would leak.
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                resume(-1)
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
            return (Double(byteCount) * 8.0 / 1_000_000) / seconds
        } catch {
            return 0
        }
    }
}
