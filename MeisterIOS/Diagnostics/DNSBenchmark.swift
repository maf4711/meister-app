import Foundation
import Network

/// Times DNS-over-HTTPS queries against well-known public resolvers. Cloudflare and
/// Google publish JSON endpoints that we hit with a few queries each — whichever
/// answers fastest wins.
actor DNSBenchmark {
    struct ProviderResult: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let endpoint: URL
        let averageMs: Double
        let failures: Int
    }

    static let providers: [(String, URL)] = [
        ("Cloudflare 1.1.1.1", URL(string: "https://cloudflare-dns.com/dns-query?name=apple.com&type=A")!),
        ("Google 8.8.8.8",     URL(string: "https://dns.google/resolve?name=apple.com&type=A")!),
        ("Quad9 9.9.9.9",      URL(string: "https://dns.quad9.net/dns-query?name=apple.com&type=A")!),
        ("AdGuard",            URL(string: "https://dns.adguard-dns.com/dns-query?name=apple.com&type=A")!),
    ]

    func run(samplesPerProvider: Int = 5) async -> [ProviderResult] {
        var results: [ProviderResult] = []
        for (name, endpoint) in Self.providers {
            var durations: [Double] = []
            var failures = 0
            for _ in 0..<samplesPerProvider {
                if let ms = await querySingle(endpoint: endpoint) {
                    durations.append(ms)
                } else {
                    failures += 1
                }
            }
            let avg = durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
            results.append(ProviderResult(
                name: name,
                endpoint: endpoint,
                averageMs: avg,
                failures: failures
            ))
        }
        return results.sorted { ($0.averageMs > 0 ? $0.averageMs : .greatestFiniteMagnitude) < ($1.averageMs > 0 ? $1.averageMs : .greatestFiniteMagnitude) }
    }

    private func querySingle(endpoint: URL) async -> Double? {
        var request = URLRequest(url: endpoint)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        let start = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = Date().timeIntervalSince(start) * 1000
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return elapsed
        } catch {
            return nil
        }
    }
}
