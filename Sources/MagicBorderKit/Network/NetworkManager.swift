import AppKit
import Foundation
import Network
import Observation

@MainActor
@Observable
public class MBNetworkManager: Observation.Observable {
    public static let shared = MBNetworkManager()

    // Config
    let port: NWEndpoint.Port = 12345
    let serviceType = "_magicborder._tcp"

    // Browser & Listener
    private var listener: NWListener?
    private var browser: NWBrowser?

    // Connections
    public var peers: [NWConnection] = []

    public struct ConnectedMachine: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let connection: NWConnection

        public static func == (lhs: ConnectedMachine, rhs: ConnectedMachine) -> Bool {
            return lhs.id == rhs.id
        }
    }
    public var connectedMachines: [ConnectedMachine] = []

    public var availablePeers: [NWBrowser.Result] = []

    // Unified Discovery
    public struct DiscoveredPeer: Identifiable, Equatable, Hashable {
        public let id = UUID()
        public let name: String
        public let endpoint: NWEndpoint
        public let type: PeerType

        public enum PeerType {
            case bonjour
            case manual
            case scanned
        }

        // Manual conformance if needed, but synthesis should work for simple types
        public static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
            return lhs.name == rhs.name && lhs.endpoint == rhs.endpoint
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(endpoint)
        }
    }

    public var discoveredPeers: [DiscoveredPeer] = []

    // Identity
    let localID = UUID()
    let localName = Host.current().localizedName ?? "Unknown Mac"

    init() {
        startAdvertising()
        startBrowsing()
        startSubnetScanning()
    }

    // MARK: - Hosting (Server)

    func startAdvertising() {
        do {
            let listener = try NWListener(using: .tcp)
            self.listener = listener

            listener.service = NWListener.Service(name: localName, type: serviceType)

            listener.newConnectionHandler = { [weak self] connection in
                print("New connection received from \(connection.endpoint)")
                Task {
                    await self?.handleNewConnection(connection)
                }
            }

            listener.stateUpdateHandler = { newState in
                print("Listener state: \(newState)")
            }

            listener.start(queue: .main)
        } catch {
            print("Failed to create listener: \(error)")
        }
    }

    // MARK: - Browsing (Client Discovery)

    func startBrowsing() {
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Keep manual/scanned peers, replace bonjour ones
                let otherPeers = self.discoveredPeers.filter { $0.type != .bonjour }

                let bonjourPeers = results.compactMap { result -> DiscoveredPeer? in
                    if case .service(let name, _, _, _) = result.endpoint {
                        if name == self.localName { return nil }
                        return DiscoveredPeer(name: name, endpoint: result.endpoint, type: .bonjour)
                    }
                    return nil
                }

                self.discoveredPeers = otherPeers + bonjourPeers
                // Legacy support (optional)
                self.availablePeers = Array(results)
            }
        }

        browser.start(queue: .main)
    }

    public func connect(to result: NWBrowser.Result) {
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        handleNewConnection(connection)
    }

    public func connect(to endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        handleNewConnection(connection)
    }

    // MARK: - Subnet Scanning

    public func startSubnetScanning() {
        print("Starting Subnet Scan...")
        let prefixes = getLocalIPPrefixes()
        guard !prefixes.isEmpty else {
            print("No local IP found for scanning.")
            return
        }

        // Scan typical /24 subnets for found local IPs
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.magicborder.scanner", attributes: .concurrent)

        for prefix in prefixes {
            print("Scanning subnet: \(prefix).1-254")
            for i in 1...254 {
                let ip = "\(prefix).\(i)"
                queue.async(group: group) {
                    self.probe(ip: ip)
                }
            }
        }
    }

    private func getLocalIPPrefixes() -> [String] {
        // Simple heuristic: Get all IPv4 addresses, take first 3 octets
        let addresses = Host.current().addresses
        let ipv4s = addresses.filter { $0.contains(".") && !$0.starts(with: "127.") }
        let prefixes = ipv4s.compactMap { ip -> String? in
            let components = ip.split(separator: ".")
            if components.count == 4 {
                return components.prefix(3).joined(separator: ".")
            }
            return nil
        }
        return Array(Set(prefixes))  // Unique
    }

    nonisolated private func probe(ip: String) {
        let host = NWEndpoint.Host(ip)
        let port = NWEndpoint.Port(integerLiteral: 15101)  // MWB Data Port

        let connection = NWConnection(to: .hostPort(host: host, port: port), using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Found Open Port at \(ip)!")
                Task { @MainActor [weak self] in
                    self?.addScannedPeer(ip: ip)
                }
                connection.cancel()
            default:
                break
            }
        }

        // Timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if connection.state != .ready {
                connection.cancel()
            }
        }

        connection.start(queue: .global())
    }

    private func addScannedPeer(ip: String) {
        // Deduplicate
        if !discoveredPeers.contains(where: { peer in
            if case .hostPort(let h, _) = peer.endpoint, case .ipv4(let ipv4) = h {
                return String(describing: ipv4) == ip
            }
            return false
        }) {
            // MWB Windows name resolution requires separate handshake or DNS lookup
            // For now, use IP as name or "PC (IP)"
            // Try reverse DNS? Dns.GetHostEntry equivalent?
            // Host.current().name(for: ip) might block.
            let name = "PC (\(ip))"
            let peer = DiscoveredPeer(
                name: name, endpoint: .hostPort(host: .init(ip), port: 15101), type: .scanned)
            discoveredPeers.append(peer)
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        self.peers.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Connection ready: \(connection.endpoint)")
                Task {
                    await self?.sendHandshake(connection: connection)
                    await self?.receiveLoop(connection: connection)
                }
            case .failed(let error):
                print("Connection failed: \(error)")
                Task {
                    await self?.removeConnection(connection)
                }
            case .cancelled:
                Task {
                    await self?.removeConnection(connection)
                }
            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    private func removeConnection(_ connection: NWConnection) {
        if let index = peers.firstIndex(where: { $0 === connection }) {
            peers.remove(at: index)
        }
        if let index = connectedMachines.firstIndex(where: { $0.connection === connection }) {
            connectedMachines.remove(at: index)
        }
    }

    // MARK: - Sending

    func sendHandshake(connection: NWConnection) {
        let info = MachineInfo(
            id: localID,
            name: localName,
            screenWidth: Double(NSScreen.main?.frame.width ?? 0),
            screenHeight: Double(NSScreen.main?.frame.height ?? 0)
        )
        let packet = PacketType.handshake(info: info)
        send(packet, to: connection)
    }

    func broadcast(_ event: RemoteEvent) {
        // Send to all connected peers
        // In a real scenario, we might only send to the "Active" remote machine
        let packet = PacketType.inputEvent(event)
        for peer in peers {
            send(packet, to: peer)
        }
    }

    private func send(_ packet: PacketType, to connection: NWConnection) {
        do {
            let data = try JSONEncoder().encode(packet)

            // Length-prefix framing
            var length = UInt32(data.count)
            let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)

            connection.send(
                content: lengthData + data,
                completion: .contentProcessed { error in
                    if let error = error {
                        print("Send error: \(error)")
                    }
                })
        } catch {
            print("Encoding error: \(error)")
        }
    }

    // MARK: - Receiving

    private func receiveLoop(connection: NWConnection) {
        // Read Length (4 bytes)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) {
            [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("Receive error: \(error)")
                return
            }

            if isComplete {
                print("Connection closed by peer")
                return
            }

            guard let content = content, content.count == 4 else {
                return  // Wait for more
            }

            let length = content.withUnsafeBytes { $0.load(as: UInt32.self) }

            // Read Body
            Task {
                await self.receiveBody(connection: connection, length: Int(length))
            }
        }
    }

    private func receiveBody(connection: NWConnection, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) {
            [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let content = content {
                Task {
                    await self.handlePacketData(content, from: connection)
                }
            }

            if !isComplete && error == nil {
                // Continue loop
                Task {
                    await self.receiveLoop(connection: connection)
                }
            }
        }
    }

    private func handlePacketData(_ data: Data, from connection: NWConnection) {
        do {
            let packet = try JSONDecoder().decode(PacketType.self, from: data)
            switch packet {
            case .handshake(let info):
                print("Handshake from \(info.name)")
                if !connectedMachines.contains(where: { $0.id == info.id }) {
                    let machine = ConnectedMachine(
                        id: info.id, name: info.name, connection: connection)
                    connectedMachines.append(machine)
                }
            case .inputEvent(let event):
                // Handle remote input
                // This simulates the event locally
                print("Received event: \(event.type)")
                self.simulateEvent(event)
            default:
                break
            }
        } catch {
            print("Decoding error: \(error)")
        }
    }

    // MARK: - Simulation (Should be moved to `InputManager` in real arch)
    private func simulateEvent(_ event: RemoteEvent) {
        // Just print for now, actual simulation requires CGEventCreate...
        print("Simulating: \(event)")
    }
}
