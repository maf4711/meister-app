import Foundation
import Network
import Observation

/// Observes the current network path and provides simple speed/latency probes.
///
/// Uses NWPathMonitor for reachability and Cloudflare's speed endpoint for
/// download measurements. Ping is approximated via a TCP connect.
@Observable
@MainActor
final class NetworkMonitor {
    private(set) var status: NWPath.Status = .unsatisfied
    private(set) var isExpensive = false
    private(set) var interface: NWInterface.InterfaceType?
    private(set) var downloadMbps: Double?
    private(set) var pingMs: Double?

    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.merados.meister.network")

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.status = path.status
                self?.isExpensive = path.isExpensive
                self?.interface = path.availableInterfaces.first?.type
            }
        }
        pathMonitor.start(queue: queue)
    }

    deinit { pathMonitor.cancel() }

    func measurePing() async {
        let start = Date()
        let connection = NWConnection(host: "1.1.1.1", port: 443, using: .tcp)
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
        pingMs = Date().timeIntervalSince(start) * 1000
    }

    func measureDownload(byteCount: Int = 1_048_576) async {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(byteCount)") else { return }
        let start = Date()
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let seconds = Date().timeIntervalSince(start)
            downloadMbps = (Double(data.count) * 8.0 / 1_000_000) / seconds
        } catch {
            downloadMbps = nil
        }
    }
}
