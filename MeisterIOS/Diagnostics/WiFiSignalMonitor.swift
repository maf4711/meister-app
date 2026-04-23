import Foundation
import Network
import Observation

/// Samples the path's best available interface and records signal updates over time.
/// Apple no longer exposes raw RSSI without a private entitlement, so the monitor
/// captures *transition events* (interface changes, expensive/cheap toggles) instead.
@Observable
@MainActor
final class WiFiSignalMonitor {
    struct Sample: Identifiable {
        let id = UUID()
        let timestamp: Date
        let interface: NWInterface.InterfaceType?
        let status: NWPath.Status
        let isExpensive: Bool
        let isConstrained: Bool
    }

    private(set) var samples: [Sample] = []
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.merados.meister.wifi")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.samples.append(Sample(
                    timestamp: .now,
                    interface: path.availableInterfaces.first?.type,
                    status: path.status,
                    isExpensive: path.isExpensive,
                    isConstrained: path.isConstrained
                ))
                if self?.samples.count ?? 0 > 500 { self?.samples.removeFirst() }
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
