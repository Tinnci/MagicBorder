import Foundation
import Network
private import OSLog

/// Actor isolating stream cipher state and packet framing off `@MainActor`.
private actor MWBChannelStreamProcessor {
    private let framer: MWBStreamFramer

    init(crypto: MWBCryptoMaterial) {
        self.framer = MWBStreamFramer(crypto: crypto)
    }

    func makeInitialIVBlock() -> Data? {
        self.framer.makeInitialIVBlock()
    }

    func encodeForSend(_ packet: MWBPacket) -> (packet: MWBPacket, encrypted: Data)? {
        self.framer.encodeForSend(packet)
    }

    func receiveEncrypted(_ data: Data) -> MWBStreamFramer.ParseResult {
        self.framer.receiveEncrypted(data)
    }

    func close() {
        self.framer.close()
    }
}

/// Manages a single encrypted MWB TCP connection (message or clipboard) with off-MainActor crypto.
@MainActor
final class MWBSessionChannel {
    let connection: NWConnection
    let kind: MWBSessionKind
    let localName: String
    let localId: Int32
    let isOutbound: Bool

    var peer: MWBPeer?
    var handshake = MWBHandshakeStateMachine()

    var onPacket: ((MWBPacket) -> Void)?
    var onDisconnected: (() -> Void)?
    var onLog: ((String) -> Void)?

    private let ioQueue = DispatchQueue(label: "com.magicborder.mwb.channel.io")
    private let processor: MWBChannelStreamProcessor

    private var hasLoggedWaiting = false
    private var clipboardAccumulator = Data()
    private var clipboardIsImage = false
    private var dragDropAccumulator = Data()
    private let heartbeatTimer = CancellableTaskSlot()
    private let clipboardBeatTimer = CancellableTaskSlot()
    private var isClosed = false

    init(
        connection: NWConnection,
        kind: MWBSessionKind,
        crypto: MWBCryptoMaterial,
        localName: String,
        localId: Int32,
        isOutbound: Bool
    ) {
        self.connection = connection
        self.kind = kind
        self.processor = MWBChannelStreamProcessor(crypto: crypto)
        self.localName = localName
        self.localId = localId
        self.isOutbound = isOutbound
    }

    deinit {
        self.heartbeatTimer.cancel()
        self.clipboardBeatTimer.cancel()
    }

    func start() {
        let processor = self.processor
        self.connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }
                await self.handleConnectionState(state, processor: processor)
            }
        }
        self.connection.start(queue: self.ioQueue)
    }

    private func handleConnectionState(
        _ state: NWConnection.State,
        processor: MWBChannelStreamProcessor
    ) async {
        switch state {
        case .ready:
            self.onLog?("✓ Session ready, kind=\(self.kind)")
            if let ivBlock = await processor.makeInitialIVBlock() {
                self.connection.send(content: ivBlock, completion: .contentProcessed { _ in })
            }
            if self.kind == .message {
                self.sendHandshakeBurst()
            } else {
                self.sendClipboardHandshake(push: false)
            }
            self.receiveLoop()
        case .waiting(let error):
            if !self.hasLoggedWaiting {
                self.onLog?("⏳ Connection waiting: \(error.localizedDescription)")
                self.hasLoggedWaiting = true
            }
        case .failed(let error):
            self.onLog?("✗ Connection failed: \(error.localizedDescription)")
            self.onDisconnected?()
        case .cancelled:
            self.onLog?("Connection cancelled")
            self.onDisconnected?()
        default:
            break
        }
    }

    func send(_ packet: MWBPacket) {
        guard !self.isClosed else { return }
        let processor = self.processor
        let connection = self.connection
        Task { [weak self] in
            guard let encoded = await processor.encodeForSend(packet) else { return }
            connection.send(content: encoded.encrypted, completion: .contentProcessed { _ in })
            let shouldLog = [.handshake, .handshakeAck, .heartbeat, .matrix].contains(encoded.packet.type)
            if shouldLog {
                await MainActor.run { [weak self] in
                    self?.onLog?(
                        "TX Packet: type=\(encoded.packet.type) src=\(encoded.packet.src) des=\(encoded.packet.des)")
                }
            }
        }
    }

    func sendClipboardHandshake(push: Bool) {
        var packet = MWBPacket()
        packet.type = push ? .clipboardPush : .clipboard
        packet.src = self.localId
        packet.des = self.peer?.id ?? 0
        packet.machineName = self.localName
        self.send(packet)
    }

    func appendClipboardChunk(_ payload: Data, isImage: Bool) {
        self.clipboardIsImage = isImage
        self.clipboardAccumulator.append(payload)
    }

    func consumeClipboardPayload() -> (data: Data, isImage: Bool)? {
        guard !self.clipboardAccumulator.isEmpty else { return nil }
        let data = self.clipboardAccumulator
        self.clipboardAccumulator = Data()
        return (data: data, isImage: self.clipboardIsImage)
    }

    func appendDragDropChunk(_ payload: Data) {
        self.dragDropAccumulator.append(payload)
    }

    func consumeDragDropPayload() -> Data? {
        guard !self.dragDropAccumulator.isEmpty else { return nil }
        let data = self.dragDropAccumulator
        self.dragDropAccumulator = Data()
        return data
    }

    private func sendHandshakeBurst() {
        let burst = self.handshake.makeOutboundHandshakeBurst(
            localId: self.localId,
            localName: self.localName)
        self.onLog?("→ Sending handshake burst (\(burst.count) packets)")
        for packet in burst {
            self.send(packet)
        }
    }

    func startHeartbeat(initial: Bool = false) {
        self.heartbeatTimer.cancel()

        if initial {
            self.send(self.makeControlPacket(type: .heartbeatEx))
        }

        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled, !self.isClosed else { break }
                self.send(self.makeControlPacket(type: .heartbeat))
            }
        }
        self.heartbeatTimer.replace(with: task)
    }

    func cancelHeartbeat() {
        self.heartbeatTimer.cancel()
    }

    func startClipboardBeat() {
        self.clipboardBeatTimer.cancel()
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled, !self.isClosed else { break }
                self.send(self.makeControlPacket(type: .clipboard))
            }
        }
        self.clipboardBeatTimer.replace(with: task)
    }

    func cancelClipboardBeat() {
        self.clipboardBeatTimer.cancel()
    }

    func sendHeartbeatAck() {
        self.send(self.makeControlPacket(type: .heartbeat))
    }

    func sendHeartbeatExL3() {
        self.send(self.makeControlPacket(type: .heartbeatExL3))
    }

    func close() {
        guard !self.isClosed else { return }
        self.isClosed = true
        self.cancelHeartbeat()
        self.cancelClipboardBeat()
        self.connection.cancel()
        let processor = self.processor
        Task {
            await processor.close()
        }
    }

    private func makeControlPacket(type: MWBPacketType) -> MWBPacket {
        var packet = MWBPacket()
        packet.type = type
        packet.src = self.localId
        packet.des = Int32(255)
        packet.machineName = self.localName
        return packet
    }

    private func receiveLoop() {
        guard !self.isClosed else { return }
        let processor = self.processor
        self.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
            [weak self] content, _, isComplete, _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }
                if let content {
                    if content.count >= 256 {
                        self.onLog?("Received \(content.count) encrypted bytes")
                    }
                    let result = await processor.receiveEncrypted(content)
                    self.emitParseResult(result)
                }
                if !isComplete {
                    self.receiveLoop()
                } else {
                    self.onDisconnected?()
                }
            }
        }
    }

    private func emitParseResult(_ result: MWBStreamFramer.ParseResult) {
        for rejected in result.rejected {
            MBLogger.network.debug(
                "MWB packet rejected. Magic=\(rejected.actualMagic) Expected=\(rejected.expectedMagic) RawType=\(rejected.rawType) Len=\(rejected.length)"
            )
            if rejected.actualMagic != 0 {
                let actualHex = String(rejected.actualMagic, radix: 16, uppercase: true)
                let expectedHex = String(rejected.expectedMagic, radix: 16, uppercase: true)
                self.onLog?("Packet Reject: Magic \(actualHex) != \(expectedHex)")
            }
        }

        for packet in result.packets {
            let shouldLog = [
                MWBPacketType.handshake, .handshakeAck, .heartbeat, .machineSwitched, .matrix,
                .captureScreenCommand,
            ].contains(packet.type)
            let suppressHandshakeLog =
                self.handshake.isVerified
                && (packet.type == .handshake || packet.type == .handshakeAck)
            if shouldLog, !suppressHandshakeLog {
                self.onLog?("RX Packet: type=\(packet.type) src=\(packet.src) des=\(packet.des)")
            }
            self.onPacket?(packet)
        }
    }
}
