public import Foundation
public import Network
private import OSLog
private import os

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

/// Discovers MagicBorder / MWB peers on the local network via Bonjour and bounded subnet scanning.
@MainActor
public final class MBDiscoveryService {
    public enum Event: Sendable {
        case found(DiscoveredPeer)
        case lost(DiscoveredPeer)
    }

    public let serviceType: String
    public let localName: String

    public let events: AsyncStream<Event>
    public private(set) var discoveredPeers: [DiscoveredPeer] = []

    private let continuation: AsyncStream<Event>.Continuation
    private let browserQueue = DispatchQueue(label: "com.magicborder.discovery.browser")
    private let scannerQueue = DispatchQueue(label: "com.magicborder.discovery.scanner", attributes: .concurrent)
    private var browser: NWBrowser?
    private let subnetScanTask = CancellableTaskSlot()

    public init(serviceType: String, localName: String) {
        self.serviceType = serviceType
        self.localName = localName
        let stream = AsyncStream<Event>.makeStream()
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    deinit {
        self.subnetScanTask.cancel()
        self.continuation.finish()
    }

    // MARK: - Browsing

    public func startBrowsing() {
        guard self.browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: self.serviceType, domain: nil), using: .tcp)
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
                    self.continuation.yield(.lost(peer))
                }
                for peer in added {
                    self.continuation.yield(.found(peer))
                }
            }
        }

        browser.start(queue: self.browserQueue)
        MBLogger.network.info("[Discovery] Bonjour browsing started.")
    }

    public func stopBrowsing() {
        self.browser?.cancel()
        self.browser = nil
    }

    // MARK: - Bounded Subnet Scanning

    public func startSubnetScanning(port: UInt16 = 15101, maxConcurrentProbes: Int = 32) {
        self.subnetScanTask.cancel()
        MBLogger.network.info("[Discovery] Starting bounded subnet scan…")
        let prefixes = Self.localIPPrefixes()
        guard !prefixes.isEmpty else {
            MBLogger.network.info("[Discovery] No local IPv4 found for scanning.")
            return
        }

        let targets = prefixes.flatMap { prefix in (1...254).map { "\(prefix).\($0)" } }
        let concurrencyLimit = max(1, maxConcurrentProbes)
        let queue = self.scannerQueue

        let task = Task { [weak self] in
            await withTaskGroup(of: String?.self) { group in
                var nextIndex = 0
                let initialCount = min(concurrencyLimit, targets.count)
                while nextIndex < initialCount {
                    let ip = targets[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await Self.probe(ip: ip, port: port, queue: queue) ? ip : nil
                    }
                }

                for await openIP in group {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    if let openIP {
                        self?.addScannedPeer(ip: openIP, port: port)
                    }
                    if nextIndex < targets.count {
                        let ip = targets[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            await Self.probe(ip: ip, port: port, queue: queue) ? ip : nil
                        }
                    }
                }
            }
        }
        self.subnetScanTask.replace(with: task)
    }

    private nonisolated static func probe(ip: String, port: UInt16, queue: DispatchQueue) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(ip), port: nwPort),
            using: .tcp)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let finished = OSAllocatedUnfairLock(initialState: false)
                let finish: @Sendable (Bool) -> Void = { isOpen in
                    let shouldResume = finished.withLock { done -> Bool in
                        guard !done else { return false }
                        done = true
                        return true
                    }
                    if shouldResume {
                        connection.cancel()
                        continuation.resume(returning: isOpen)
                    }
                }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        MBLogger.network.info("[Discovery] Open port at \(ip)")
                        finish(true)
                    case .failed, .cancelled:
                        finish(false)
                    default:
                        break
                    }
                }

                queue.asyncAfter(deadline: .now() + 0.5) {
                    finish(false)
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    private func addScannedPeer(ip: String, port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let endpoint = NWEndpoint.hostPort(host: .init(ip), port: nwPort)
        guard
            !self.discoveredPeers.contains(where: {
                if case .hostPort(let h, _) = $0.endpoint, case .ipv4(let v4) = h {
                    return String(describing: v4) == ip
                }
                return false
            })
        else { return }

        let peer = DiscoveredPeer(name: "PC (\(ip))", endpoint: endpoint, type: .scanned)
        self.discoveredPeers.append(peer)
        self.continuation.yield(.found(peer))
    }

    // MARK: - Manual Peer

    public func addManualPeer(ip: String, port: UInt16 = 15101) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let endpoint = NWEndpoint.hostPort(host: .init(ip), port: nwPort)
        guard !self.discoveredPeers.contains(where: { $0.endpoint == endpoint }) else { return }
        let peer = DiscoveredPeer(name: ip, endpoint: endpoint, type: .manual)
        self.discoveredPeers.append(peer)
        self.continuation.yield(.found(peer))
    }

    // MARK: - Lifecycle

    public func stopAll() {
        self.stopBrowsing()
        self.subnetScanTask.cancel()
    }

    private static func localIPPrefixes() -> [String] {
        let addresses = Host.current().addresses
        let prefixes =
            addresses
            .filter { $0.contains(".") && !$0.hasPrefix("127.") }
            .compactMap { ip -> String? in
                let parts = ip.split(separator: ".")
                guard parts.count == 4 else { return nil }
                return parts.prefix(3).joined(separator: ".")
            }
        return Array(Set(prefixes))
    }
}
