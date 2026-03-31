import Foundation
import Network
import OSLog

// MARK: - DiscoveredPeer

/// A machine found on the local network before a connection is established.
public struct DiscoveredPeer: Identifiable, Equatable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    public let endpoint: NWEndpoint
    public let type: PeerType

    public enum PeerType: Sendable {
        case bonjour
        case manual
        case scanned
    }

    public static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
        lhs.name == rhs.name && lhs.endpoint == rhs.endpoint
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.name)
        hasher.combine(self.endpoint)
    }
}

// MARK: - MBDiscoveryService

/// Discovers MagicBorder / MWB peers on the local network via Bonjour and subnet scanning.
///
/// Ownership: this service owns `NWBrowser` and the subnet scanner.
/// The `NWListener` (inbound connection acceptance) remains in `MBNetworkManager`
/// until a dedicated `MBConnectionRegistry` is extracted (Phase 3).
///
/// Consume events via the `AsyncStream<Event>` returned by `events`:
/// ```swift
/// Task {
///     for await event in discoveryService.events {
///         switch event { case .found(let peer): … }
///     }
/// }
/// ```
@MainActor
public final class MBDiscoveryService {
    // MARK: - Event

    public enum Event: Sendable {
        case found(DiscoveredPeer)
        case lost(DiscoveredPeer)
    }

    // MARK: - Public API

    public let serviceType: String
    public let localName: String

    /// Continuously emits `.found` / `.lost` events as peers appear and disappear.
    public private(set) var events: AsyncStream<Event>

    /// Current snapshot of all known peers (updated before each event is emitted).
    public private(set) var discoveredPeers: [DiscoveredPeer] = []

    // MARK: - Private

    private var continuation: AsyncStream<Event>.Continuation?
    private var browser: NWBrowser?

    // MARK: - Init

    public init(serviceType: String, localName: String) {
        self.serviceType = serviceType
        self.localName = localName
        var cont: AsyncStream<Event>.Continuation?
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    deinit {
        continuation?.finish()
    }

    // MARK: - Browsing

    public func startBrowsing() {
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        self.browser = browser
        let localName = self.localName

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let bonjourPeers = results.compactMap { result -> DiscoveredPeer? in
                    guard case .service(let name, _, _, _) = result.endpoint,
                          name != localName
                    else { return nil }
                    return DiscoveredPeer(name: name, endpoint: result.endpoint, type: .bonjour)
                }

                let existing = self.discoveredPeers.filter { $0.type != .bonjour }
                let added = bonjourPeers.filter { !self.discoveredPeers.contains($0) }
                let removed = self.discoveredPeers.filter {
                    $0.type == .bonjour && !bonjourPeers.contains($0)
                }

                self.discoveredPeers = existing + bonjourPeers

                for peer in removed {
                    self.continuation?.yield(.lost(peer))
                }
                for peer in added {
                    self.continuation?.yield(.found(peer))
                }
            }
        }

        browser.start(queue: .main)
        MBLogger.network.info("[Discovery] Bonjour browsing started.")
    }

    public func stopBrowsing() {
        self.browser?.cancel()
        self.browser = nil
    }

    // MARK: - Subnet Scanning

    public func startSubnetScanning(port: UInt16 = 15101) {
        MBLogger.network.info("[Discovery] Starting subnet scan…")
        let prefixes = Self.localIPPrefixes()
        guard !prefixes.isEmpty else {
            MBLogger.network.info("[Discovery] No local IPv4 found for scanning.")
            return
        }
        let queue = DispatchQueue(label: "com.magicborder.scanner", attributes: .concurrent)
        for prefix in prefixes {
            for i in 1 ... 254 {
                let ip = "\(prefix).\(i)"
                queue.async { [weak self] in self?.probe(ip: ip, port: port) }
            }
        }
    }

    private nonisolated func probe(ip: String, port: UInt16) {
        let host = NWEndpoint.Host(ip)
        let nwPort = NWEndpoint.Port(integerLiteral: port)
        let connection = NWConnection(to: .hostPort(host: host, port: nwPort), using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                MBLogger.network.info("[Discovery] Open port at \(ip)")
                Task { @MainActor [weak self] in self?.addScannedPeer(ip: ip, port: port) }
                connection.cancel()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if connection.state != .ready { connection.cancel() }
        }
        connection.start(queue: .global())
    }

    private func addScannedPeer(ip: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(host: .init(ip), port: .init(integerLiteral: port))
        guard !self.discoveredPeers.contains(where: {
            if case .hostPort(let h, _) = $0.endpoint, case .ipv4(let v4) = h {
                return String(describing: v4) == ip
            }
            return false
        }) else { return }

        let peer = DiscoveredPeer(name: "PC (\(ip))", endpoint: endpoint, type: .scanned)
        self.discoveredPeers.append(peer)
        self.continuation?.yield(.found(peer))
    }

    // MARK: - Manual Peer

    public func addManualPeer(ip: String, port: UInt16 = 15101) {
        let endpoint = NWEndpoint.hostPort(host: .init(ip), port: .init(integerLiteral: port))
        guard !self.discoveredPeers.contains(where: { $0.endpoint == endpoint }) else { return }
        let peer = DiscoveredPeer(name: ip, endpoint: endpoint, type: .manual)
        self.discoveredPeers.append(peer)
        self.continuation?.yield(.found(peer))
    }

    // MARK: - Lifecycle

    public func stopAll() {
        self.stopBrowsing()
    }

    // MARK: - Helpers

    private static func localIPPrefixes() -> [String] {
        let addresses = Host.current().addresses
        let prefixes = addresses
            .filter { $0.contains(".") && !$0.hasPrefix("127.") }
            .compactMap { ip -> String? in
                let parts = ip.split(separator: ".")
                guard parts.count == 4 else { return nil }
                return parts.prefix(3).joined(separator: ".")
            }
        return Array(Set(prefixes))
    }
}
