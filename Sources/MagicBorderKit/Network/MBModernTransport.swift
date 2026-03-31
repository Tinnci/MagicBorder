import AppKit
import CryptoKit
import Foundation
import Network

@MainActor
public final class MBModernTransport: MBTransport {
    public var events: AsyncStream<MBTransportEvent>
    public var peers: [NWConnection] { self.registry.peers }

    private let registry: MBConnectionRegistry
    private let localID: UUID
    private let localName: String
    private var securityKey: String
    private var continuation: AsyncStream<MBTransportEvent>.Continuation?

    public init(
        serviceType: String,
        localName: String,
        localID: UUID,
        securityKey: String)
    {
        self.registry = MBConnectionRegistry(serviceType: serviceType, localName: localName)
        self.localID = localID
        self.localName = localName
        self.securityKey = securityKey

        var continuation: AsyncStream<MBTransportEvent>.Continuation?
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    deinit {
        self.continuation?.finish()
    }

    public func start() {
        self.registry.startListening()
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in self.registry.events {
                switch event {
                case .connectionReady(let connection):
                    self.sendHandshake(connection: connection)
                    self.receiveLoop(connection: connection)
                case .connectionLost(_, let machineId):
                    if let machineId {
                        self.continuation?.yield(.machineDisconnected(machineId))
                    }
                }
            }
        }
    }

    public func stop() {
        self.registry.stopListening()
    }

    public func updateConfiguration(securityKey: String, settings _: MBCompatibilitySettings) {
        self.securityKey = securityKey
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
        self.continuation?.yield(.machineDisconnected(machine.id))
    }

    public func reconnect(machine: Machine) {
        self.registry.reconnect(machineId: machine.id)
        self.continuation?.yield(.machineDisconnected(machine.id))
    }

    public func activate(machine _: Machine?) {}

    public func centerRemoteCursor() {}

    public func sendRemoteInput(snapshot: EventSnapshot, activeMachineId: UUID?) {
        guard let remoteEvent = MBInputManager.shared.convertToRemoteEvent(snapshot: snapshot) else { return }
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

    public func sendScreenCapture(_ data: Data, to _: Int32?) {
        self.sendClipboardImage(data, activeMachineId: nil)
    }

    public func sendMachineMatrix(names _: [String], twoRow _: Bool, swap _: Bool) {}

    public func sendFileDrop(_: [URL]) {}

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
        var info = MachineInfo(
            id: self.localID,
            name: self.localName,
            screenWidth: Double(NSScreen.main?.frame.width ?? 0),
            screenHeight: Double(NSScreen.main?.frame.height ?? 0),
            signature: nil)

        if let keyData = self.securityKey.data(using: .utf8),
           let idData = info.id.uuidString.data(using: .utf8)
        {
            let key = SymmetricKey(data: keyData)
            let signature = HMAC<SHA256>.authenticationCode(for: idData, using: key)
            info.signature = Data(signature).base64EncodedString()
        }

        self.send(.handshake(info: info), to: connection)
    }

    private func send(_ packet: PacketType, to connection: NWConnection) {
        do {
            let data = try JSONEncoder().encode(packet)
            var length = UInt32(data.count)
            let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            connection.send(
                content: lengthData + data,
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
            guard let self else { return }

            if let error {
                MBLogger.network.error("[ModernTransport] Receive error: \(error)")
                return
            }

            if isComplete {
                MBLogger.network.info("[ModernTransport] Connection closed by peer")
                return
            }

            guard let content, content.count == 4 else { return }
            let length = content.withUnsafeBytes { $0.load(as: UInt32.self) }
            Task { @MainActor [weak self] in
                self?.receiveBody(connection: connection, length: Int(length))
            }
        }
    }

    private func receiveBody(connection: NWConnection, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let content {
                Task { @MainActor [weak self] in
                    self?.handlePacketData(content, from: connection)
                }
            }

            if !isComplete, error == nil {
                Task { @MainActor [weak self] in
                    self?.receiveLoop(connection: connection)
                }
            }
        }
    }

    private func handlePacketData(_ data: Data, from connection: NWConnection) {
        do {
            let packet = try JSONDecoder().decode(PacketType.self, from: data)
            switch packet {
            case .handshake(let info):
                if let signature = info.signature,
                   let keyData = self.securityKey.data(using: .utf8),
                   let idData = info.id.uuidString.data(using: .utf8)
                {
                    let key = SymmetricKey(data: keyData)
                    let computed = HMAC<SHA256>.authenticationCode(for: idData, using: key)
                    let computedString = Data(computed).base64EncodedString()
                    if signature != computedString {
                        MBLogger.security.error("[ModernTransport] Invalid signature from \(info.name)")
                        connection.cancel()
                        return
                    }
                }

                let machine = Machine(
                    id: info.id,
                    name: info.name,
                    state: .connected,
                    screenSize: CGSize(width: info.screenWidth, height: info.screenHeight))
                self.registry.register(connection, for: info.id)
                self.continuation?.yield(.machineConnected(machine))

            case .inputEvent(let event):
                self.continuation?.yield(.remoteEvent(event))

            case .clipboardData(let payload):
                switch payload.type {
                case .text:
                    if let text = String(data: payload.content, encoding: .utf8) {
                        self.continuation?.yield(.clipboardText(text))
                    }
                case .image:
                    self.continuation?.yield(.clipboardImage(payload.content))
                }

            default:
                break
            }
        } catch {
            MBLogger.network.error("[ModernTransport] Decoding error: \(error.localizedDescription)")
        }
    }
}
