public import Foundation
public import Network
private import OSLog

// MARK: - MBConnectionEvent

public enum MBConnectionEvent: Sendable {
    /// A TCP connection became ready to exchange application-layer packets.
    case connectionReady(NWConnection)
    /// A connection was lost (failed or cancelled).
    case connectionLost(NWConnection, machineId: UUID?)
}

// MARK: - MBConnectionRegistry

/// Owns all `NWConnection` lifecycle: the `NWListener` (inbound TCP accept),
/// outbound connections, and the `machineId <-> NWConnection` mapping.
@MainActor
public final class MBConnectionRegistry {
    public private(set) var peers: [NWConnection] = []
    public private(set) var machineConnections: [UUID: NWConnection] = [:]

    public let events: AsyncStream<MBConnectionEvent>
    private let continuation: AsyncStream<MBConnectionEvent>.Continuation

    private let ioQueue = DispatchQueue(label: "com.magicborder.modern.registry.io")
    private var listener: NWListener?
    private let serviceType: String
    private let localName: String
    private let port: NWEndpoint.Port?

    public init(serviceType: String, localName: String, port: NWEndpoint.Port? = nil) {
        self.serviceType = serviceType
        self.localName = localName
        self.port = port
        let stream = AsyncStream<MBConnectionEvent>.makeStream()
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    deinit {
        self.continuation.finish()
    }

    public func startListening() {
        guard self.listener == nil else { return }
        do {
            let listener: NWListener =
                if let port = self.port {
                    try NWListener(using: .tcp, on: port)
                } else {
                    try NWListener(using: .tcp)
                }
            listener.service = NWListener.Service(name: self.localName, type: self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in self?.add(connection) }
            }
            listener.stateUpdateHandler = { state in
                MBLogger.network.info("[Registry] Listener state: \(String(describing: state))")
            }
            listener.start(queue: self.ioQueue)
            self.listener = listener
            MBLogger.network.info("[Registry] Listener started (\(self.localName)).")
        } catch {
            MBLogger.network.error("[Registry] Failed to create listener: \(error.localizedDescription)")
        }
    }

    public func stopListening() {
        self.listener?.cancel()
        self.listener = nil
        for peer in self.peers {
            peer.cancel()
        }
        self.peers.removeAll()
        self.machineConnections.removeAll()
    }

    public func connect(to result: NWBrowser.Result) {
        self.add(NWConnection(to: result.endpoint, using: .tcp))
    }

    public func connect(to endpoint: NWEndpoint) {
        self.add(NWConnection(to: endpoint, using: .tcp))
    }

    public func connectToHost(_ ip: String, port: UInt16 = 12345) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        self.add(NWConnection(to: .hostPort(host: .init(ip), port: nwPort), using: .tcp))
    }

    public func register(_ connection: NWConnection, for machineId: UUID) {
        self.machineConnections[machineId] = connection
    }

    public func disconnect(machineId: UUID) {
        if let conn = self.machineConnections[machineId] {
            conn.cancel()
        }
    }

    public func reconnect(machineId: UUID) {
        guard let conn = self.machineConnections[machineId] else { return }
        let endpoint = conn.endpoint
        conn.cancel()
        self.machineConnections.removeValue(forKey: machineId)
        self.peers.removeAll { $0 === conn }
        self.connect(to: endpoint)
    }

    public func connection(for machineId: UUID) -> NWConnection? {
        self.machineConnections[machineId]
    }

    public func machineId(for connection: NWConnection) -> UUID? {
        self.machineConnections.first(where: { $0.value === connection })?.key
    }

    private func add(_ connection: NWConnection) {
        self.peers.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    MBLogger.network.info(
                        "[Registry] Connection ready: \(String(describing: connection.endpoint))")
                    self.continuation.yield(.connectionReady(connection))
                case .failed(let error):
                    MBLogger.network.error(
                        "[Registry] Connection failed: \(error.localizedDescription)")
                    let machineId = self.machineId(for: connection)
                    self.remove(connection)
                    self.continuation.yield(.connectionLost(connection, machineId: machineId))
                case .cancelled:
                    let machineId = self.machineId(for: connection)
                    self.remove(connection)
                    self.continuation.yield(.connectionLost(connection, machineId: machineId))
                default:
                    break
                }
            }
        }

        connection.start(queue: self.ioQueue)
    }

    private func remove(_ connection: NWConnection) {
        self.peers.removeAll { $0 === connection }
        if let id = self.machineConnections.first(where: { $0.value === connection })?.key {
            self.machineConnections.removeValue(forKey: id)
        }
    }
}
