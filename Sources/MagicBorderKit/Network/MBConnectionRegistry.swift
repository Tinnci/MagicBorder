import Foundation
import Network
import OSLog

// MARK: - MBConnectionEvent

public enum MBConnectionEvent: Sendable {
    /// A TCP connection became ready to exchange application-layer packets.
    case connectionReady(NWConnection)
    /// A connection was lost (failed or cancelled).
    case connectionLost(NWConnection)
}

// MARK: - MBConnectionRegistry

/// Owns all NWConnection lifecycle: the NWListener (inbound TCP accept),
/// outbound connections, and the machineId ↔ NWConnection mapping.
///
/// Application-layer protocol (handshake, packet framing, receiveLoop) stays
/// in NetworkManager until Phase 3c/3d extraction.
///
/// Consume lifecycle events via `events: AsyncStream<MBConnectionEvent>`.
@MainActor
public final class MBConnectionRegistry {
    // MARK: - Public state

    /// All raw transport connections (inbound + outbound, pre- and post-handshake).
    public private(set) var peers: [NWConnection] = []

    /// UUID → NWConnection mapping; populated after handshake completes.
    public private(set) var machineConnections: [UUID: NWConnection] = [:]

    // MARK: - Events

    public private(set) var events: AsyncStream<MBConnectionEvent>
    private var continuation: AsyncStream<MBConnectionEvent>.Continuation?

    // MARK: - Listener

    private var listener: NWListener?
    private let serviceType: String
    private let localName: String

    // MARK: - Init

    public init(serviceType: String, localName: String) {
        self.serviceType = serviceType
        self.localName = localName
        var cont: AsyncStream<MBConnectionEvent>.Continuation?
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    deinit {
        continuation?.finish()
    }

    // MARK: - Listener (Bonjour advertising + inbound TCP accept)

    public func startListening() {
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: self.localName, type: self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in self?.add(connection) }
            }
            listener.stateUpdateHandler = { state in
                MBLogger.network.info("[Registry] Listener state: \(String(describing: state))")
            }
            listener.start(queue: .main)
            self.listener = listener
            MBLogger.network.info("[Registry] Listener started (\(self.localName)).")
        } catch {
            MBLogger.network.error("[Registry] Failed to create listener: \(error.localizedDescription)")
        }
    }

    public func stopListening() {
        self.listener?.cancel()
        self.listener = nil
    }

    // MARK: - Outbound connections

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

    // MARK: - Registration (post-handshake)

    /// Called by the application layer once a handshake identifies the remote machine.
    public func register(_ connection: NWConnection, for machineId: UUID) {
        self.machineConnections[machineId] = connection
    }

    // MARK: - Disconnect / Reconnect

    public func disconnect(machineId: UUID) {
        if let conn = machineConnections[machineId] {
            conn.cancel()
            // `.connectionLost` event will fire from the stateUpdateHandler
        }
    }

    public func reconnect(machineId: UUID) {
        guard let conn = machineConnections[machineId] else { return }
        let endpoint = conn.endpoint
        conn.cancel()
        self.machineConnections.removeValue(forKey: machineId)
        self.peers.removeAll { $0 === conn }
        self.connect(to: endpoint)
    }

    // MARK: - Queries

    public func connection(for machineId: UUID) -> NWConnection? {
        self.machineConnections[machineId]
    }

    public func activeConnection(activeMachineId: UUID?) -> NWConnection? {
        guard let id = activeMachineId else { return nil }
        return self.machineConnections[id]
    }

    public func machineId(for connection: NWConnection) -> UUID? {
        self.machineConnections.first(where: { $0.value === connection })?.key
    }

    // MARK: - Private helpers

    private func add(_ connection: NWConnection) {
        self.peers.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    MBLogger.network.info(
                        "[Registry] Connection ready: \(String(describing: connection.endpoint))")
                    self?.continuation?.yield(.connectionReady(connection))
                case .failed(let error):
                    MBLogger.network.error(
                        "[Registry] Connection failed: \(error.localizedDescription)")
                    self?.remove(connection)
                    self?.continuation?.yield(.connectionLost(connection))
                case .cancelled:
                    self?.remove(connection)
                    self?.continuation?.yield(.connectionLost(connection))
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    private func remove(_ connection: NWConnection) {
        self.peers.removeAll { $0 === connection }
        if let id = machineConnections.first(where: { $0.value === connection })?.key {
            self.machineConnections.removeValue(forKey: id)
        }
    }
}
