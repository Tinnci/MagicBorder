import CoreGraphics
public import Foundation
public import Network
private import OSLog

@MainActor
public final class MBModernTransport: MBTransport {
    public let events: AsyncStream<MBTransportEvent>
    public var peers: [NWConnection] { self.registry.peers }

    private let registry: MBConnectionRegistry
    private let localID: UUID
    private let localName: String
    private var securityKey: String
    private var invertScroll: Bool = false
    private var scrollSpeed: Double = 1.0
    private let screenGeometry: any ScreenGeometryProviding
    private let codec = ModernPacketCodec()
    private let continuation: AsyncStream<MBTransportEvent>.Continuation
    private let registryEventsTask = CancellableTaskSlot()

    public init(
        serviceType: String,
        localName: String,
        localID: UUID,
        securityKey: String,
        port: NWEndpoint.Port? = nil,
        screenGeometry: any ScreenGeometryProviding = SystemScreenGeometryProvider()
    ) {
        self.registry = MBConnectionRegistry(serviceType: serviceType, localName: localName, port: port)
        self.localID = localID
        self.localName = localName
        self.securityKey = securityKey
        self.screenGeometry = screenGeometry

        let stream = AsyncStream<MBTransportEvent>.makeStream()
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    deinit {
        self.registryEventsTask.cancel()
        self.continuation.finish()
    }

    public func start() {
        self.registry.startListening()
        guard !self.registryEventsTask.isActive else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in self.registry.events {
                switch event {
                case .connectionReady(let connection):
                    self.sendHandshake(connection: connection)
                    self.receiveLoop(connection: connection)
                case .connectionLost(_, let machineId):
                    if let machineId {
                        self.continuation.yield(.machineDisconnected(machineId))
                    }
                }
            }
        }
        self.registryEventsTask.replace(with: task)
    }

    public func stop() {
        self.registryEventsTask.cancel()
        self.registry.stopListening()
    }

    public func updateConfiguration(securityKey: String, settings: MBCompatibilitySettings) {
        self.securityKey = securityKey
        self.invertScroll = settings.invertRemoteScroll
        self.scrollSpeed = settings.remoteScrollSpeed
    }

    public func connect(to endpoint: NWEndpoint) {
        self.registry.connect(to: endpoint)
    }

    public func connect(to result: NWBrowser.Result) {
        self.registry.connect(to: result)
    }

    public func connectToHost(ip: String, port: UInt16) {
        self.registry.connectToHost(ip, port: port)
    }

    public func disconnect(machine: Machine) {
        self.registry.disconnect(machineId: machine.id)
        self.continuation.yield(.machineDisconnected(machine.id))
    }

    public func reconnect(machine: Machine) {
        self.registry.reconnect(machineId: machine.id)
        self.continuation.yield(.machineDisconnected(machine.id))
    }

    public func sendRemoteInput(snapshot: EventSnapshot, activeMachineId: UUID?) {
        guard
            let remoteEvent = MBRemoteEventConverter.convert(
                snapshot: snapshot,
                invertScroll: self.invertScroll,
                scrollSpeed: self.scrollSpeed)
        else { return }
        self.sendPacket(.inputEvent(remoteEvent), activeMachineId: activeMachineId)
    }

    public func sendClipboardText(_ text: String, activeMachineId: UUID?) {
        let payload = ClipboardPayload(content: Data(text.utf8), type: .text)
        self.sendPacket(.clipboardData(payload), activeMachineId: activeMachineId)
    }

    public func sendClipboardImage(_ data: Data, activeMachineId: UUID?) {
        let payload = ClipboardPayload(content: data, type: .image)
        self.sendPacket(.clipboardData(payload), activeMachineId: activeMachineId)
    }

    private func sendPacket(_ packet: PacketType, activeMachineId: UUID?) {
        if let activeMachineId,
            let connection = self.registry.connection(for: activeMachineId)
        {
            self.send(packet, to: connection)
        } else {
            for peer in self.peers {
                self.send(packet, to: peer)
            }
        }
    }

    private func sendHandshake(connection: NWConnection) {
        let screenSize = self.screenGeometry.mainScreenFrame?.size ?? .zero
        let signature = ModernPacketCodec.sign(machineID: self.localID, securityKey: self.securityKey)
        let info = MachineInfo(
            id: self.localID,
            name: self.localName,
            screenWidth: Double(screenSize.width),
            screenHeight: Double(screenSize.height),
            signature: signature)
        self.send(.handshake(info: info), to: connection)
    }

    private func send(_ packet: PacketType, to connection: NWConnection) {
        do {
            let frame = try self.codec.encodeFrame(packet)
            connection.send(
                content: frame,
                completion: .contentProcessed { error in
                    if let error {
                        MBLogger.network.error("[ModernTransport] Send error: \(error)")
                    }
                })
        } catch {
            MBLogger.network.error("[ModernTransport] Encoding error: \(error)")
        }
    }

    private func receiveLoop(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    MBLogger.network.error("[ModernTransport] Receive error: \(error)")
                    return
                }
                if isComplete {
                    MBLogger.network.info("[ModernTransport] Connection closed by peer")
                    return
                }
                guard let content, let length = self.codec.decodeLengthHeader(content) else {
                    MBLogger.security.error("[ModernTransport] Invalid or oversized frame header; closing connection")
                    connection.cancel()
                    return
                }
                self.receiveBody(connection: connection, length: length)
            }
        }
    }

    private func receiveBody(connection: NWConnection, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) {
            [weak self] content, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let content {
                    self.handlePacketData(content, from: connection)
                }
                if !isComplete, error == nil {
                    self.receiveLoop(connection: connection)
                }
            }
        }
    }

    private func handlePacketData(_ data: Data, from connection: NWConnection) {
        do {
            let packet = try self.codec.decodePacket(data)
            switch packet {
            case .handshake(let info):
                guard
                    ModernPacketCodec.verify(
                        signature: info.signature,
                        machineID: info.id,
                        securityKey: self.securityKey)
                else {
                    MBLogger.security.error("[ModernTransport] Invalid or missing signature from \(info.name)")
                    connection.cancel()
                    return
                }

                let machine = Machine(
                    id: info.id,
                    name: info.name,
                    state: .connected,
                    screenSize: CGSize(width: info.screenWidth, height: info.screenHeight))
                self.registry.register(connection, for: info.id)
                self.continuation.yield(.machineConnected(machine))

            case .inputEvent(let event):
                self.continuation.yield(.remoteEvent(event))

            case .clipboardData(let payload):
                switch payload.type {
                case .text:
                    if let text = String(data: payload.content, encoding: .utf8) {
                        self.continuation.yield(.clipboardText(text))
                    }
                case .image:
                    self.continuation.yield(.clipboardImage(payload.content))
                }

            case .heartbeat, .bye:
                break
            }
        } catch {
            MBLogger.network.error("[ModernTransport] Decoding error: \(error.localizedDescription)")
        }
    }
}
