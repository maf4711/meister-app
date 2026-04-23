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
            results.append(await tcpPing(host: host))
        }
        return results
    }

    private func tcpPing(host: String) async -> Double {
        let start = Date()
        let connection = NWConnection(host: .init(host), port: 443, using: .tcp)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                    connection.cancel()
                case .failed, .cancelled:
                    continuation.resume()
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global())
        }
        return Date().timeIntervalSince(start) * 1000
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
