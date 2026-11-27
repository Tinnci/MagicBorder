import AppKit
public import Foundation
import Network

@MainActor
public final class MWBCompatibilityService: MWBCompatibilityServicing {
    private let listenerQueue = DispatchQueue(label: "com.magicborder.mwb.listener")
    private let pasteboard: any PasteboardAccessing

    private var cryptoMaterial: MWBCryptoMaterial?
    private var messageListener: NWListener?
    private var clipboardListener: NWListener?
    private var messageSessions: [MWBSessionChannel] = []
    private var clipboardSessions: [MWBSessionChannel] = []

    private let localName: String
    private let localId: Int32
    private var messagePort: UInt16
    private var clipboardPort: UInt16
    private var currentSecurityKey = ""
    private var reconnectPolicy = MWBReconnectPolicy()
    private let reconnectTask = CancellableTaskSlot()
    private let keyDerivationTask = CancellableTaskSlot()

    public let events: AsyncStream<MWBCompatibilityEvent>
    private let continuation: AsyncStream<MWBCompatibilityEvent>.Continuation

    public init(
        localName: String,
        localId: Int32,
        messagePort: UInt16 = 15101,
        clipboardPort: UInt16 = 15100,
        pasteboard: any PasteboardAccessing = SystemPasteboard()
    ) {
        let stream = AsyncStream<MWBCompatibilityEvent>.makeStream()
        self.events = stream.stream
        self.continuation = stream.continuation
        self.localName = localName
        self.localId = localId
        self.messagePort = messagePort
        self.clipboardPort = clipboardPort
        self.pasteboard = pasteboard
    }

    deinit {
        self.reconnectTask.cancel()
        self.keyDerivationTask.cancel()
        self.continuation.finish()
    }

    private func emit(_ event: MWBCompatibilityEvent) {
        self.continuation.yield(event)
    }

    public func start(securityKey: String) {
        let trimmed = securityKey.replacingOccurrences(of: " ", with: "")
        guard trimmed.count >= 16 else {
            self.emit(.log("MWB service not started: security key too short"))
            return
        }
        self.currentSecurityKey = securityKey
        self.deriveAndStartListeners(securityKey: securityKey)
    }

    public func stop() {
        self.keyDerivationTask.cancel()
        self.reconnectTask.cancel()
        self.reconnectPolicy.reset()
        self.messageListener?.cancel()
        self.clipboardListener?.cancel()
        self.messageListener = nil
        self.clipboardListener = nil
        for session in self.messageSessions + self.clipboardSessions {
            session.close()
        }
        self.messageSessions.removeAll()
        self.clipboardSessions.removeAll()
    }

    public func updateSecurityKey(_ key: String) {
        let trimmed = key.replacingOccurrences(of: " ", with: "")
        guard trimmed.count >= 16 else {
            self.stop()
            self.cryptoMaterial = nil
            self.emit(.log("MWB service stopped: security key too short"))
            return
        }
        self.currentSecurityKey = key
        let task = Task { @MainActor [weak self] in
            let material = await Task.detached(priority: .userInitiated) {
                MWBKeyDerivation.derive(from: key)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.cryptoMaterial = material
        }
        self.keyDerivationTask.replace(with: task)
    }

    public func updatePorts(messagePort: UInt16, clipboardPort: UInt16) {
        guard self.messagePort != messagePort || self.clipboardPort != clipboardPort else { return }
        self.messagePort = messagePort
        self.clipboardPort = clipboardPort
        let savedKey = self.currentSecurityKey
        self.stop()
        if !savedKey.isEmpty {
            self.start(securityKey: savedKey)
        }
    }

    public func connectToHost(ip: String, messagePort: UInt16? = nil, clipboardPort: UInt16? = nil) {
        guard !ip.isEmpty else { return }
        let trimmedKey = self.currentSecurityKey.replacingOccurrences(of: " ", with: "")
        guard trimmedKey.count >= 16 else {
            self.emit(.error("Cannot connect: security key is invalid or empty"))
            return
        }

        let targetMsgPort = messagePort ?? self.messagePort
        let targetClipPort = clipboardPort ?? self.clipboardPort
        self.emit(.log("Connecting to \(ip):\(targetMsgPort) and \(ip):\(targetClipPort)"))

        self.reconnectPolicy.recordConnectTarget(
            host: ip,
            messagePort: targetMsgPort,
            clipboardPort: targetClipPort)
        self.reconnectTask.cancel()

        if self.cryptoMaterial == nil {
            self.cryptoMaterial = MWBKeyDerivation.derive(from: self.currentSecurityKey)
        }

        guard let nwPort = NWEndpoint.Port(rawValue: targetMsgPort) else { return }
        let connection = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(ip), port: nwPort),
            using: .tcp)
        self.handleNewConnection(connection, kind: .message, isOutbound: true)
    }

    public func disconnect(peerId: Int32) {
        let matching = self.sessions(for: peerId)
        guard !matching.isEmpty else { return }
        self.stopAutoReconnect()
        for session in matching where session.kind == .message {
            self.reconnectPolicy.suppressReconnect(for: ObjectIdentifier(session))
        }
        for session in matching {
            session.close()
        }
    }

    public func reconnect(peerId: Int32) {
        let matching = self.sessions(for: peerId)
        guard let messageSession = matching.first(where: { $0.kind == .message }),
            let (host, msgPort) = Self.hostPort(from: messageSession.connection.endpoint)
        else { return }

        for session in matching where session.kind == .message {
            self.reconnectPolicy.suppressReconnect(for: ObjectIdentifier(session))
        }
        for session in matching {
            session.close()
        }

        self.connectToHost(
            ip: host,
            messagePort: msgPort,
            clipboardPort: self.reconnectPolicy.lastClipboardPort ?? self.clipboardPort)
    }

    public func stopAutoReconnect() {
        self.reconnectTask.cancel()
        self.reconnectPolicy.reset()
    }

    // MARK: - Outbound Commands

    public func sendMachineMatrix(_ machines: [String], twoRow: Bool = false, swap: Bool = false) {
        guard !self.messageSessions.isEmpty else { return }
        for packet in MWBClipboardCodec.encodeMatrixPackets(machines: machines, twoRow: twoRow, swap: swap) {
            self.broadcast(packet, to: self.messageSessions)
        }
    }

    public func sendNextMachine(targetId: Int32?) {
        guard !self.messageSessions.isEmpty else { return }
        var packet = MWBPacket()
        packet.type = .nextMachine
        packet.src = self.localId
        packet.des = targetId ?? 0
        self.broadcast(packet, to: self.messageSessions)
    }

    public func sendMouseEvent(x: Int32, y: Int32, wheel: Int32, flags: Int32) {
        guard !self.messageSessions.isEmpty else { return }
        var packet = MWBPacket()
        packet.type = .mouse
        packet.src = self.localId
        packet.des = Int32(255)
        packet.mouseX = x
        packet.mouseY = y
        packet.mouseWheel = wheel
        packet.mouseFlags = flags
        self.broadcast(packet, to: self.messageSessions)
    }

    public func sendKeyEvent(keyCode: Int32, flags: Int32) {
        guard !self.messageSessions.isEmpty else { return }
        var packet = MWBPacket()
        packet.type = .keyboard
        packet.src = self.localId
        packet.des = Int32(255)
        packet.keyCode = keyCode
        packet.keyFlags = flags
        self.broadcast(packet, to: self.messageSessions)
    }

    public func sendHideMouse() {
        guard !self.messageSessions.isEmpty else { return }
        var packet = MWBPacket()
        packet.type = .hideMouse
        packet.src = self.localId
        packet.des = Int32(255)
        self.broadcast(packet, to: self.messageSessions)
    }

    public func sendFileDrop(_ urls: [URL]) {
        guard !self.messageSessions.isEmpty else { return }
        let payload = MWBClipboardCodec.encodeFileDrop(urls)
        let chunks = MWBClipboardCodec.chunkPackets(type: .clipboardDragDrop, data: payload, localId: self.localId)
        for packet in chunks {
            self.broadcast(packet, to: self.messageSessions)
        }

        var beginPacket = MWBPacket()
        beginPacket.type = .clipboardDragDropOperation
        beginPacket.src = self.localId
        beginPacket.des = Int32(255)
        self.broadcast(beginPacket, to: self.messageSessions)

        var endPacket = MWBPacket()
        endPacket.type = .clipboardDragDropEnd
        endPacket.src = self.localId
        endPacket.des = Int32(255)
        self.broadcast(endPacket, to: self.messageSessions)
    }

    public func sendClipboardText(_ text: String) {
        guard let target = self.clipboardTargets().first else { return }
        self.sendClipboardText(text, via: target)
    }

    public func sendClipboardImage(_ data: Data) {
        guard let target = self.clipboardTargets().first else { return }
        self.sendClipboardImage(data, via: target)
    }

    public func sendClipboardImage(_ data: Data, to peerId: Int32?) {
        guard
            let target = self.clipboardTargets().first(where: { $0.peer?.id == peerId })
                ?? self.messageSessions.first(where: { $0.peer?.id == peerId })
        else { return }
        self.sendClipboardImage(data, via: target)
    }

    // MARK: - Private Setup & Session Lifecycle

    private func deriveAndStartListeners(securityKey: String) {
        let task = Task { @MainActor [weak self] in
            let material = await Task.detached(priority: .userInitiated) {
                MWBKeyDerivation.derive(from: securityKey)
            }.value
            guard !Task.isCancelled, let self, let material else { return }
            self.cryptoMaterial = material
            self.messageListener = self.startListener(port: self.messagePort, kind: .message)
            self.clipboardListener = self.startListener(port: self.clipboardPort, kind: .clipboard)
            self.emit(
                .log(
                    "MWB service started. messagePort=\(self.messagePort) clipboardPort=\(self.clipboardPort)"))
        }
        self.keyDerivationTask.replace(with: task)
    }

    private func startListener(port portValue: UInt16, kind: MWBSessionKind) -> NWListener? {
        guard let port = NWEndpoint.Port(rawValue: portValue) else {
            let message = "MWB invalid \(kind) port: \(portValue)"
            self.emit(.error(message))
            self.emit(.log(message))
            return nil
        }

        do {
            let listener = try NWListener(using: .tcp, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection, kind: kind, isOutbound: false)
                }
            }
            listener.start(queue: self.listenerQueue)
            return listener
        } catch {
            let message = "MWB \(kind) listener failed: \(error.localizedDescription)"
            self.emit(.error(message))
            self.emit(.log(message))
            return nil
        }
    }

    private func handleNewConnection(
        _ connection: NWConnection,
        kind: MWBSessionKind,
        isOutbound: Bool
    ) {
        guard let material = self.cryptoMaterial else {
            connection.cancel()
            return
        }

        let session = MWBSessionChannel(
            connection: connection,
            kind: kind,
            crypto: material,
            localName: self.localName,
            localId: self.localId,
            isOutbound: isOutbound)

        session.onPacket = { [weak self, weak session] packet in
            guard let self, let session else { return }
            self.handlePacket(packet, from: session)
        }
        session.onLog = { [weak self] message in
            self?.emit(.log(message))
        }
        session.onDisconnected = { [weak self, weak session] in
            guard let self, let session else { return }
            self.removeSession(session)
        }

        switch kind {
        case .message:
            self.messageSessions.append(session)
        case .clipboard:
            self.clipboardSessions.append(session)
        }

        session.start()
    }

    private func removeSession(_ session: MWBSessionChannel) {
        session.close()
        self.messageSessions.removeAll { $0 === session }
        self.clipboardSessions.removeAll { $0 === session }

        if let peer = session.peer {
            self.emit(.log("⚠ Connection lost from '\(peer.name)' (ID=\(peer.id))"))
            self.emit(.disconnected(peer))
        }

        if session.kind == .message {
            for clipboard in self.clipboardSessions {
                clipboard.close()
            }
            self.clipboardSessions.removeAll()
        }

        self.evaluateReconnect(after: session)
    }

    private func evaluateReconnect(after session: MWBSessionChannel) {
        let decision = self.reconnectPolicy.evaluateDisconnect(
            sessionID: ObjectIdentifier(session),
            isOutbound: session.isOutbound,
            kind: session.kind,
            remainingMessageSessions: self.messageSessions.count)

        switch decision {
        case .skip:
            break
        case .exhausted(let host, let maxAttempts):
            self.emit(.log("⏹ Auto-reconnect stopped after \(maxAttempts) attempts"))
            self.emit(.reconnectStopped(host))
        case .schedule(let host, let msgPort, let clipPort, _):
            guard !self.reconnectTask.isActive else { return }
            let task = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, let self else { return }
                self.emit(.log("⟳ Reconnecting to \(host)..."))
                self.emit(.reconnectAttempt(host))
                self.connectToHost(ip: host, messagePort: msgPort, clipboardPort: clipPort)
            }
            self.reconnectTask.replace(with: task)
        }
    }

    private func connectClipboardIfNeeded() {
        guard self.clipboardSessions.isEmpty,
            let host = self.reconnectPolicy.lastHost,
            let portValue = self.reconnectPolicy.lastClipboardPort,
            let port = NWEndpoint.Port(rawValue: portValue)
        else { return }

        let connection = NWConnection(to: .hostPort(host: .init(host), port: port), using: .tcp)
        self.handleNewConnection(connection, kind: .clipboard, isOutbound: true)
    }

    private func dedupeSessions(using session: MWBSessionChannel) {
        guard let peer = session.peer else { return }
        if session.kind == .message {
            self.closeDuplicates(in: &self.messageSessions, keeping: session, peer: peer)
        } else {
            self.closeDuplicates(in: &self.clipboardSessions, keeping: session, peer: peer)
        }
    }

    private func closeDuplicates(
        in list: inout [MWBSessionChannel],
        keeping session: MWBSessionChannel,
        peer: MWBPeer
    ) {
        for other in list where other !== session {
            if other.peer?.id == peer.id || other.peer?.name == peer.name {
                other.close()
            }
        }
        list.removeAll { $0 !== session && ($0.peer?.id == peer.id || $0.peer?.name == peer.name) }
    }

    // MARK: - Packet Dispatch

    private func handlePacket(_ packet: MWBPacket, from session: MWBSessionChannel) {
        if session.handshake.isVerified,
            packet.type == .handshake || packet.type == .handshakeAck
        {
            return
        }

        switch packet.type {
        case .handshake, .handshakeAck, .hello, .hi, .awake, .heartbeat, .heartbeatEx, .heartbeatExL2,
            .heartbeatExL3, .byeBye:
            self.handleLifecyclePacket(packet, from: session)
        case .mouse, .keyboard, .machineSwitched, .nextMachine, .hideMouse, .captureScreenCommand, .matrix:
            self.handleControlOrInputPacket(packet, from: session)
        case .clipboard, .clipboardPush, .clipboardText, .clipboardImage, .clipboardDataEnd, .clipboardAsk,
            .clipboardCapture, .clipboardDragDrop, .explorerDragDrop, .clipboardDragDropOperation,
            .clipboardDragDropEnd:
            self.handleClipboardOrDropPacket(packet, from: session)
        default:
            break
        }
    }

    private func handleLifecyclePacket(_ packet: MWBPacket, from session: MWBSessionChannel) {
        switch packet.type {
        case .handshake:
            if session.handshake.pendingPeerName == nil {
                session.handshake.pendingPeerName = packet.machineName
                self.emit(.log("Handshake received from '\(packet.machineName)' (pending)"))
            }
            session.send(session.handshake.makeHandshakeAck(for: packet, localName: self.localName))
        case .handshakeAck:
            switch session.handshake.processAck(packet) {
            case .verified(let peer):
                session.peer = peer
                self.reconnectPolicy.markConnected()
                self.reconnectTask.cancel()
                self.emit(.log("✓ HandshakeAck VERIFIED from '\(peer.name)' (ID=\(peer.id))"))
                self.emit(.connected(peer))
                self.dedupeSessions(using: session)
                session.startHeartbeat(initial: true)
                if session.kind == .message {
                    session.startClipboardBeat()
                    self.connectClipboardIfNeeded()
                }
            case .failedFirstTime:
                self.emit(.log("✗ HandshakeAck FAILED verification"))
            case .ignored:
                break
            }
        case .hello:
            self.ensurePeerConnected(packet, on: session)
            session.sendHeartbeatAck()
        case .hi, .awake, .heartbeat, .heartbeatEx:
            self.ensurePeerConnected(packet, on: session)
        case .heartbeatExL2:
            session.sendHeartbeatExL3()
        case .byeBye:
            if let peer = session.peer {
                self.emit(.disconnected(peer))
            }
        default:
            break
        }
    }

    private func handleControlOrInputPacket(_ packet: MWBPacket, from session: MWBSessionChannel) {
        switch packet.type {
        case .mouse:
            self.emit(
                .remoteMouse(
                    MWBMouseEvent(
                        x: packet.mouseX,
                        y: packet.mouseY,
                        wheel: packet.mouseWheel,
                        flags: packet.mouseFlags)))
        case .keyboard:
            self.emit(.remoteKey(MWBKeyEvent(keyCode: packet.keyCode, flags: packet.keyFlags)))
        case .machineSwitched, .nextMachine:
            self.emit(.machineSwitched(session.peer))
        case .hideMouse:
            self.emit(.hideMouse)
        case .captureScreenCommand:
            self.emit(.captureScreen(packet.src))
        case .matrix:
            let decoded = MWBClipboardCodec.decodeMatrixPacket(packet)
            if !decoded.names.isEmpty {
                self.emit(.machineMatrix(decoded.names))
            }
            self.emit(.matrixOptionsUpdated(twoRow: decoded.twoRow, swap: decoded.swap))
        default:
            break
        }
    }

    private func handleClipboardOrDropPacket(_ packet: MWBPacket, from session: MWBSessionChannel) {
        switch packet.type {
        case .clipboard, .clipboardPush:
            guard session.kind == .clipboard else { return }
            let peer = MWBPeer(id: packet.src, name: packet.machineName)
            session.peer = peer
            self.emit(.log("Clipboard handshake received from '\(peer.name)' (ID=\(peer.id))"))
            self.emit(.connected(peer))
            session.sendClipboardHandshake(push: packet.type == .clipboardPush)
        case .clipboardText:
            session.appendClipboardChunk(packet.clipboardPayload, isImage: false)
        case .clipboardImage:
            session.appendClipboardChunk(packet.clipboardPayload, isImage: true)
        case .clipboardDataEnd:
            guard let payload = session.consumeClipboardPayload() else { return }
            if payload.isImage {
                self.emit(.clipboardImage(payload.data))
            } else if let text = MWBClipboardCodec.decodeClipboardText(payload.data) {
                self.emit(.clipboardText(text))
            }
        case .clipboardAsk, .clipboardCapture:
            self.sendClipboardFromPasteboard()
        case .clipboardDragDrop, .explorerDragDrop:
            session.appendDragDropChunk(packet.clipboardPayload)
            self.emit(.dragDropBegin(session.peer?.name))
        case .clipboardDragDropOperation:
            self.emit(.dragDropOperation(session.peer?.name))
        case .clipboardDragDropEnd:
            if let payload = session.consumeDragDropPayload(),
                let urls = MWBClipboardCodec.decodeFileDrop(payload)
            {
                self.emit(.clipboardFiles(urls))
            }
            self.emit(.dragDropEnd)
        default:
            break
        }
    }

    private func ensurePeerConnected(_ packet: MWBPacket, on session: MWBSessionChannel) {
        if session.peer == nil {
            session.peer = MWBPeer(id: packet.src, name: packet.machineName)
        }
        if let peer = session.peer {
            self.emit(.connected(peer))
        }
    }

    private func sendClipboardFromPasteboard() {
        guard let session = self.clipboardTargets().first else { return }
        if let string = self.pasteboard.readString() {
            self.sendClipboardText(string, via: session)
            return
        }
        if let png = self.pasteboard.readPNGData() {
            self.sendClipboardImage(png, via: session)
            return
        }
        if let tiff = self.pasteboard.readImageTIFFData(),
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        {
            self.sendClipboardImage(png, via: session)
        }
    }

    private func sendClipboardText(_ text: String, via session: MWBSessionChannel) {
        guard let compressed = MWBClipboardCodec.encodeClipboardText(text) else { return }
        self.sendClipboardData(compressed, isImage: false, via: session)
    }

    private func sendClipboardImage(_ imageData: Data, via session: MWBSessionChannel) {
        self.sendClipboardData(imageData, isImage: true, via: session)
    }

    private func sendClipboardData(_ data: Data, isImage: Bool, via session: MWBSessionChannel) {
        let type: MWBPacketType = isImage ? .clipboardImage : .clipboardText
        for packet in MWBClipboardCodec.chunkPackets(type: type, data: data, localId: self.localId) {
            session.send(packet)
        }

        var endPacket = MWBPacket()
        endPacket.type = .clipboardDataEnd
        endPacket.src = self.localId
        endPacket.des = Int32(255)
        session.send(endPacket)
    }

    private func clipboardTargets() -> [MWBSessionChannel] {
        self.clipboardSessions.isEmpty ? self.messageSessions : self.clipboardSessions
    }

    private func sessions(for peerId: Int32) -> [MWBSessionChannel] {
        (self.messageSessions + self.clipboardSessions).filter { $0.peer?.id == peerId }
    }

    private func broadcast(_ packet: MWBPacket, to sessions: [MWBSessionChannel]) {
        for session in sessions {
            session.send(packet)
        }
    }

    private static func hostPort(from endpoint: NWEndpoint) -> (String, UInt16)? {
        guard case .hostPort(let host, let port) = endpoint else { return nil }
        return (self.hostString(host), port.rawValue)
    }

    private static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .name(let name, _):
            name
        case .ipv4(let address):
            "\(address)"
        case .ipv6(let address):
            "\(address)"
        @unknown default:
            "\(host)"
        }
    }
}
