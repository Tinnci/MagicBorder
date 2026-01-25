import AppKit
import Foundation
import Network

public enum MBProtocolMode: String {
    case modern
    case mwbCompatibility
    case dual
}

public struct MWBPeer: Equatable, Hashable {
    public let id: Int32
    public let name: String
}

@MainActor
public final class MWBCompatibilityService: ObservableObject {
    private let crypto = MWBCrypto.shared
    private var messageListener: NWListener?
    private var clipboardListener: NWListener?

    private var messageSessions: [MWBSession] = []
    private var clipboardSessions: [MWBSession] = []

    private let localName: String
    private let localId: Int32
    private var messagePort: UInt16
    private var clipboardPort: UInt16
    private var currentSecurityKey: String = ""
    private var lastConnectHost: String?
    private var lastConnectMessagePort: UInt16?
    private var lastConnectClipboardPort: UInt16?
    private var reconnectTask: Task<Void, Never>?

    public var onConnected: ((MWBPeer) -> Void)?
    public var onDisconnected: ((MWBPeer) -> Void)?
    public var onRemoteMouse: ((MWBMouseEvent) -> Void)?
    public var onRemoteKey: ((MWBKeyEvent) -> Void)?
    public var onMachineSwitched: ((MWBPeer?) -> Void)?
    public var onMachineMatrix: (([String]) -> Void)?
    public var onMatrixOptions: ((Bool, Bool) -> Void)?
    public var onClipboardText: ((String) -> Void)?
    public var onClipboardImage: ((Data) -> Void)?
    public var onClipboardFiles: (([URL]) -> Void)?
    public var onHideMouse: (() -> Void)?
    public var onDragDropOperation: ((String?) -> Void)?
    public var onDragDropBegin: ((String?) -> Void)?
    public var onDragDropEnd: (() -> Void)?
    public var onCaptureScreen: ((Int32?) -> Void)?
    public var onLog: ((String) -> Void)?
    public var onError: ((String) -> Void)?

    public init(
        localName: String, localId: Int32, messagePort: UInt16 = 15101,
        clipboardPort: UInt16 = 15100)
    {
        self.localName = localName
        self.localId = localId
        self.messagePort = messagePort
        self.clipboardPort = clipboardPort
    }

    public func start(securityKey: String) {
        let trimmed = securityKey.replacingOccurrences(of: " ", with: "")
        guard trimmed.count >= 16 else {
            onLog?("MWB service not started: security key too short")
            return
        }
        currentSecurityKey = securityKey
        crypto.deriveKey(from: securityKey)
        startMessageListener()
        startClipboardListener()
        onLog?("MWB service started. messagePort=\(messagePort) clipboardPort=\(clipboardPort)")
    }

    public func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        lastConnectHost = nil
        lastConnectMessagePort = nil
        lastConnectClipboardPort = nil
        messageListener?.cancel()
        clipboardListener?.cancel()
        messageListener = nil
        clipboardListener = nil
        messageSessions.removeAll()
        clipboardSessions.removeAll()
    }

    public func updateSecurityKey(_ key: String) {
        let trimmed = key.replacingOccurrences(of: " ", with: "")
        guard trimmed.count >= 16 else {
            stop()
            onLog?("MWB service stopped: security key too short")
            return
        }
        currentSecurityKey = key
        crypto.deriveKey(from: key)
    }

    public func updatePorts(messagePort: UInt16, clipboardPort: UInt16) {
        guard self.messagePort != messagePort || self.clipboardPort != clipboardPort else { return }
        self.messagePort = messagePort
        self.clipboardPort = clipboardPort
        stop()
        if !currentSecurityKey.isEmpty {
            start(securityKey: currentSecurityKey)
        }
    }

    public func connectToHost(ip: String, messagePort: UInt16? = nil, clipboardPort: UInt16? = nil) {
        guard !ip.isEmpty else { return }
        let trimmedKey = currentSecurityKey.replacingOccurrences(of: " ", with: "")
        guard trimmedKey.count >= 16 else {
            onError?("Cannot connect: security key is invalid or empty")
            return
        }
        let host = NWEndpoint.Host(ip)

        onLog?(
            "Connecting to \(ip):\(messagePort ?? self.messagePort) and \(ip):\(clipboardPort ?? self.clipboardPort)")

        lastConnectHost = ip
        lastConnectMessagePort = messagePort ?? self.messagePort
        lastConnectClipboardPort = clipboardPort ?? self.clipboardPort

        if let port = NWEndpoint.Port(rawValue: messagePort ?? self.messagePort) {
            let connection = NWConnection(to: .hostPort(host: host, port: port), using: .tcp)
            handleNewConnection(connection, kind: .message, isOutbound: true)
        }
    }

    private func connectClipboardIfNeeded() {
        guard clipboardSessions.isEmpty else { return }
        guard let host = lastConnectHost,
              let portValue = lastConnectClipboardPort
        else { return }
        guard let port = NWEndpoint.Port(rawValue: portValue) else { return }

        let connection = NWConnection(to: .hostPort(host: .init(host), port: port), using: .tcp)
        handleNewConnection(connection, kind: .clipboard, isOutbound: true)
    }

    public func sendMachineMatrix(_ machines: [String], twoRow: Bool = false, swap: Bool = false) {
        guard !messageSessions.isEmpty else { return }

        // C# MWB expects 4 packets, one for each slot (Src 1...4)
        // Src = Index (1-based)
        // MachineName = Name of machine at that index
        // Flags (TwoRow/Swap) only checked on the 4th packet (Src=4)

        let paddedMachines = machines + Array(repeating: "", count: max(0, 4 - machines.count))
        let flags: UInt8 = (swap ? 0x02 : 0x00) | (twoRow ? 0x04 : 0x00)

        for (index, name) in paddedMachines.prefix(4).enumerated() {
            var packet = MWBPacket()
            packet.rawType = MWBPacketType.matrix.rawValue | flags
            packet.src = Int32(index + 1)
            packet.des = Int32(255)
            packet.machineName = name

            // C# logic: MachineStuff.UpdateMachineMatrix ignores packets with Src > 4
            // and only updates settings when Src == 4.
            broadcast(packet, to: messageSessions)
        }
    }

    public func sendNextMachine(targetId: Int32?) {
        guard !messageSessions.isEmpty else { return }
        var packet = MWBPacket()
        packet.type = .nextMachine
        packet.src = localId
        packet.des = targetId ?? 0
        broadcast(packet, to: messageSessions)
    }

    public func sendMouseEvent(x: Int32, y: Int32, wheel: Int32, flags: Int32) {
        guard !messageSessions.isEmpty else { return }
        var packet = MWBPacket()
        packet.type = .mouse
        packet.src = localId
        packet.des = Int32(255)
        packet.mouseX = x
        packet.mouseY = y
        packet.mouseWheel = wheel
        packet.mouseFlags = flags
        broadcast(packet, to: messageSessions)
    }

    public func sendKeyEvent(keyCode: Int32, flags: Int32) {
        guard !messageSessions.isEmpty else { return }
        var packet = MWBPacket()
        packet.type = .keyboard
        packet.src = localId
        packet.des = Int32(255)
        packet.keyCode = keyCode
        packet.keyFlags = flags
        broadcast(packet, to: messageSessions)
    }

    public func sendHideMouse() {
        guard !messageSessions.isEmpty else { return }
        var packet = MWBPacket()
        packet.type = .hideMouse
        packet.src = localId
        packet.des = Int32(255)
        broadcast(packet, to: messageSessions)
    }

    public func sendFileDrop(_ urls: [URL]) {
        guard !messageSessions.isEmpty else { return }
        let payload = encodeFileDrop(urls)
        sendChunked(type: .clipboardDragDrop, data: payload, to: messageSessions)

        var beginPacket = MWBPacket()
        beginPacket.type = .clipboardDragDropOperation
        beginPacket.src = localId
        beginPacket.des = Int32(255)
        broadcast(beginPacket, to: messageSessions)

        var endPacket = MWBPacket()
        endPacket.type = .clipboardDragDropEnd
        endPacket.src = localId
        endPacket.des = Int32(255)
        broadcast(endPacket, to: messageSessions)
    }

    public func sendClipboardText(_ text: String) {
        guard let target = clipboardTargets().first else { return }
        sendClipboardText(text, via: target)
    }

    public func sendClipboardImage(_ data: Data) {
        guard let target = clipboardTargets().first else { return }
        sendClipboardImage(data, via: target)
    }

    public func sendClipboardImage(_ data: Data, to peerId: Int32?) {
        guard
            let target = clipboardTargets().first(where: { $0.peer?.id == peerId })
            ?? messageSessions.first(where: { $0.peer?.id == peerId })
        else { return }
        sendClipboardImage(data, via: target)
    }

    public func sendClipboardFromPasteboard() {
        guard let session = clipboardTargets().first else { return }
        if let string = NSPasteboard.general.string(forType: .string) {
            sendClipboardText(string, via: session)
            return
        }

        if let image = NSImage(pasteboard: NSPasteboard.general),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:])
        {
            sendClipboardImage(png, via: session)
        }
    }

    private func clipboardTargets() -> [MWBSession] {
        if !clipboardSessions.isEmpty {
            return clipboardSessions
        }
        return messageSessions
    }

    private func startMessageListener() {
        do {
            guard let port = NWEndpoint.Port(rawValue: messagePort) else {
                let message = "MWB invalid message port: \(messagePort)"
                onError?(message)
                onLog?(message)
                return
            }
            let listener = try NWListener(using: .tcp, on: port)
            messageListener = listener
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection, kind: .message, isOutbound: false)
                }
            }
            listener.start(queue: DispatchQueue.main)
        } catch {
            let message = "MWB message listener failed: \(error.localizedDescription)"
            onError?(message)
            onLog?(message)
        }
    }

    private func startClipboardListener() {
        do {
            guard let port = NWEndpoint.Port(rawValue: clipboardPort) else {
                let message = "MWB invalid clipboard port: \(clipboardPort)"
                onError?(message)
                onLog?(message)
                return
            }
            let listener = try NWListener(using: .tcp, on: port)
            clipboardListener = listener
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection, kind: .clipboard, isOutbound: false)
                }
            }
            listener.start(queue: DispatchQueue.main)
        } catch {
            let message = "MWB clipboard listener failed: \(error.localizedDescription)"
            onError?(message)
            onLog?(message)
        }
    }

    private func handleNewConnection(
        _ connection: NWConnection,
        kind: MWBSessionKind,
        isOutbound: Bool)
    {
        guard crypto.sessionKey != nil else {
            connection.cancel()
            return
        }

        let session = MWBSession(
            connection: connection,
            kind: kind,
            crypto: crypto,
            localName: localName,
            localId: localId,
            isOutbound: isOutbound)

        session.onPacket = { [weak self, weak session] packet in
            guard let self, let session else { return }
            handlePacket(packet, from: session)
        }

        session.onError = { [weak self] message in
            self?.onError?(message)
            self?.onLog?(message)
        }

        session.onLog = { [weak self] message in
            self?.onLog?(message)
        }

        session.onDisconnected = { [weak self, weak session] in
            guard let self, let session else { return }
            removeSession(session)
        }

        switch kind {
        case .message:
            messageSessions.append(session)
        case .clipboard:
            clipboardSessions.append(session)
        }

        session.start()
    }

    private func removeSession(_ session: MWBSession) {
        // 取消心跳任务
        session.cancelHeartbeat()
        session.cancelClipboardBeat()

        messageSessions.removeAll { $0 === session }
        clipboardSessions.removeAll { $0 === session }

        if let peer = session.peer {
            onLog?("⚠ Connection lost from '\(peer.name)' (ID=\(peer.id))")
            onDisconnected?(peer)
        }

        if session.kind == .message {
            for clipboard in clipboardSessions {
                clipboard.close()
            }
            clipboardSessions.removeAll()
        }

        scheduleReconnectIfNeeded(for: session)
    }

    private func dedupeSessions(using session: MWBSession) {
        guard let peer = session.peer else { return }
        if session.kind == .message {
            for other in messageSessions where other !== session {
                if other.peer?.id == peer.id || other.peer?.name == peer.name {
                    other.close()
                }
            }
            messageSessions.removeAll {
                $0 !== session && ($0.peer?.id == peer.id || $0.peer?.name == peer.name)
            }
        } else {
            for other in clipboardSessions where other !== session {
                if other.peer?.id == peer.id || other.peer?.name == peer.name {
                    other.close()
                }
            }
            clipboardSessions.removeAll {
                $0 !== session && ($0.peer?.id == peer.id || $0.peer?.name == peer.name)
            }
        }
    }

    private func scheduleReconnectIfNeeded(for session: MWBSession) {
        guard session.isOutbound, session.kind == .message else { return }
        guard messageSessions.isEmpty else { return }
        guard let host = lastConnectHost,
              let msgPort = lastConnectMessagePort,
              let clipPort = lastConnectClipboardPort
        else { return }

        if reconnectTask?.isCancelled == false { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { [weak self] in
                self?.onLog?("⟳ Reconnecting to \(host)...")
                self?.connectToHost(ip: host, messagePort: msgPort, clipboardPort: clipPort)
            }
        }
    }

    private func handlePacket(_ packet: MWBPacket, from session: MWBSession) {
        if session.isHandshakeVerified,
           packet.type == .handshake || packet.type == .handshakeAck
        {
            return
        }

        switch packet.type {
        case .handshake:
            if session.pendingPeerName == nil {
                session.pendingPeerName = packet.machineName
                onLog?("Handshake received from '\(packet.machineName)' (pending)")
            }

            var ack = packet
            ack.type = .handshakeAck
            ack.src = 0
            ack.machineName = localName
            ack.machine1 = ~packet.machine1
            ack.machine2 = ~packet.machine2
            ack.machine3 = ~packet.machine3
            ack.machine4 = ~packet.machine4
            session.send(ack)
        case .handshakeAck:
            guard !session.isHandshakeVerified else { break }

            if let (m1, m2, m3, m4) = session.handshakeChallenge,
               packet.machine1 == ~m1,
               packet.machine2 == ~m2,
               packet.machine3 == ~m3,
               packet.machine4 == ~m4
            {
                session.peer = MWBPeer(id: packet.src, name: packet.machineName)
                session.isHandshakeVerified = true
                session.handshakeChallenge = nil
                session.handshakeAckFailures = 0

                if let peer = session.peer {
                    onLog?("✓ HandshakeAck VERIFIED from '\(peer.name)' (ID=\(peer.id))")
                    onConnected?(peer)
                    dedupeSessions(using: session)
                    session.startHeartbeat(initial: true)
                    if session.kind == .message {
                        session.startClipboardBeat()
                        connectClipboardIfNeeded()
                    }
                }
            } else if session.handshakeChallenge != nil {
                session.handshakeAckFailures += 1
                if session.handshakeAckFailures == 1 {
                    onLog?("✗ HandshakeAck FAILED verification")
                }
            }
        case .hello:
            if session.peer == nil {
                session.peer = MWBPeer(id: packet.src, name: packet.machineName)
            }
            if let peer = session.peer {
                onConnected?(peer)
            }
            session.sendHeartbeatAck()
        case .hi, .awake, .heartbeat, .heartbeatEx:
            if session.peer == nil {
                session.peer = MWBPeer(id: packet.src, name: packet.machineName)
            }
            if let peer = session.peer {
                onConnected?(peer)
            }
        case .heartbeatExL2:
            session.sendHeartbeatExL3()
        case .heartbeatExL3:
            break
        case .byeBye:
            if let peer = session.peer {
                onDisconnected?(peer)
            }
        case .clipboard, .clipboardPush:
            if session.kind == .clipboard {
                session.peer = MWBPeer(id: packet.src, name: packet.machineName)
                if let peer = session.peer {
                    onLog?("Clipboard handshake received from '\(peer.name)' (ID=\(peer.id))")
                    onConnected?(peer)
                }
                session.sendClipboardHandshake(push: packet.type == .clipboardPush)
            }
        case .mouse:
            let event = MWBMouseEvent(
                x: packet.mouseX, y: packet.mouseY, wheel: packet.mouseWheel,
                flags: packet.mouseFlags)
            onRemoteMouse?(event)
        case .keyboard:
            let event = MWBKeyEvent(keyCode: packet.keyCode, flags: packet.keyFlags)
            onRemoteKey?(event)
        case .clipboardText:
            session.appendClipboardChunk(packet.clipboardPayload, isImage: false)
        case .clipboardImage:
            session.appendClipboardChunk(packet.clipboardPayload, isImage: true)
        case .clipboardDataEnd:
            if let payload = session.consumeClipboardPayload() {
                if payload.isImage {
                    onClipboardImage?(payload.data)
                } else if let text = decodeClipboardText(payload.data) {
                    onClipboardText?(text)
                }
            }
        case .clipboardAsk:
            sendClipboardFromPasteboard()
        case .clipboardCapture:
            sendClipboardFromPasteboard()
        case .clipboardDragDrop, .explorerDragDrop:
            session.appendDragDropChunk(packet.clipboardPayload)
            onDragDropBegin?(session.peer?.name)
        case .clipboardDragDropOperation:
            onDragDropOperation?(session.peer?.name)
        case .clipboardDragDropEnd:
            if let payload = session.consumeDragDropPayload(),
               let urls = decodeFileDrop(payload)
            {
                onClipboardFiles?(urls)
            }
            onDragDropEnd?()
        case .machineSwitched:
            onMachineSwitched?(session.peer)
        case .nextMachine:
            onMachineSwitched?(session.peer)
        case .hideMouse:
            onHideMouse?()
        case .captureScreenCommand:
            onCaptureScreen?(packet.src)
        case .matrix:
            // Basic matrix info: machineName field contains a CSV on some builds
            let matrix = packet.machineName.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if !matrix.isEmpty {
                onMachineMatrix?(matrix)
            }
            let flags = packet.rawType & 0x0F
            let swap = (flags & 0x02) != 0
            let twoRow = (flags & 0x04) != 0
            onMatrixOptions?(twoRow, swap)
        default:
            break
        }
    }

    private func sendClipboardText(_ text: String, via session: MWBSession) {
        guard let textData = text.data(using: .utf16LittleEndian),
              let compressed = MWBCompression.deflateCompress(textData)
        else { return }
        sendClipboardData(compressed, isImage: false, via: session)
    }

    private func sendClipboardImage(_ imageData: Data, via session: MWBSession) {
        sendClipboardData(imageData, isImage: true, via: session)
    }

    private func sendClipboardData(_ data: Data, isImage: Bool, via session: MWBSession) {
        let type: MWBPacketType = isImage ? .clipboardImage : .clipboardText
        sendChunked(type: type, data: data, to: [session])

        var endPacket = MWBPacket()
        endPacket.type = .clipboardDataEnd
        endPacket.src = localId
        endPacket.des = Int32(255)
        session.send(endPacket)
    }

    private func sendChunked(type: MWBPacketType, data: Data, to sessions: [MWBSession]) {
        let chunkSize = 48
        var index = 0
        while index < data.count {
            let end = min(index + chunkSize, data.count)
            let chunk = data.subdata(in: index ..< end)
            var packet = MWBPacket()
            packet.type = type
            packet.src = localId
            packet.des = Int32(255)
            packet.clipboardPayload = chunk
            broadcast(packet, to: sessions)
            index = end
        }
    }

    private func broadcast(_ packet: MWBPacket, to sessions: [MWBSession]) {
        for session in sessions {
            session.send(packet)
        }
    }

    private func encodeFileDrop(_ urls: [URL]) -> Data {
        let paths = urls.map(\.path)
        let joined = paths.joined(separator: "\0") + "\0\0"
        return joined.data(using: .utf16LittleEndian) ?? Data()
    }

    private func decodeClipboardText(_ data: Data) -> String? {
        guard let decompressed = MWBCompression.deflateDecompress(data) else { return nil }
        return String(data: decompressed, encoding: .utf16LittleEndian)
    }

    private func decodeFileDrop(_ data: Data) -> [URL]? {
        guard let string = String(data: data, encoding: .utf16LittleEndian) else { return nil }
        let paths = string.split(separator: "\0").map { String($0) }.filter { !$0.isEmpty }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        return urls.isEmpty ? nil : urls
    }
}

public struct MWBMouseEvent {
    public let x: Int32
    public let y: Int32
    public let wheel: Int32
    public let flags: Int32
}

public struct MWBKeyEvent {
    public let keyCode: Int32
    public let flags: Int32
}

private enum MWBSessionKind {
    case message
    case clipboard
}

@MainActor
private final class MWBSession {
    let connection: NWConnection
    let kind: MWBSessionKind
    let crypto: MWBCrypto
    let localName: String
    let localId: Int32
    let isOutbound: Bool

    var peer: MWBPeer?

    var onPacket: ((MWBPacket) -> Void)?
    var onDisconnected: (() -> Void)?
    var onError: ((String) -> Void)?
    var onLog: ((String) -> Void)?

    private var encryptor: MWBStreamCipher?
    private var decryptor: MWBStreamCipher?

    private var encryptedBuffer = Data()
    private var plainBuffer = Data()
    private var initialBlockDiscarded = false

    var handshakeChallenge: (Int32, Int32, Int32, Int32)?
    var isHandshakeVerified = false
    var handshakeAckFailures = 0
    var pendingPeerName: String?
    private var hasLoggedWaiting = false

    private var clipboardAccumulator = Data()
    private var clipboardIsImage = false
    private var dragDropAccumulator = Data()
    private var heartbeatTimer: Task<Void, Never>?
    private var clipboardBeatTimer: Task<Void, Never>?
    private var helloBurstTask: Task<Void, Never>?
    private var packetCounter: Int32 = 0

    init(
        connection: NWConnection,
        kind: MWBSessionKind,
        crypto: MWBCrypto,
        localName: String,
        localId: Int32,
        isOutbound: Bool)
    {
        self.connection = connection
        self.kind = kind
        self.crypto = crypto
        self.localName = localName
        self.localId = localId
        self.isOutbound = isOutbound
        encryptor = crypto.makeEncryptor()
        decryptor = crypto.makeDecryptor()
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    onLog?("✓ Session ready, kind=\(kind)")
                    sendInitialIVBlock()
                    if kind == .message {
                        sendHandshakeBurst()
                    } else if kind == .clipboard {
                        sendClipboardHandshake(push: false)
                    }
                    receiveLoop()
                case .waiting(let error):
                    // 只输出一次waiting状态，避免日志刷屏
                    if !hasLoggedWaiting {
                        onLog?("⏳ Connection waiting: \(error.localizedDescription)")
                        hasLoggedWaiting = true
                    }
                case .failed(let error):
                    onLog?("✗ Connection failed: \(error.localizedDescription)")
                    onDisconnected?()
                case .cancelled:
                    onLog?("Connection cancelled")
                    onDisconnected?()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    func send(_ packet: MWBPacket) {
        guard let packetToSend = finalize(packet),
              let encrypted = encrypt(packetToSend.data)
        else { return }

        // 只输出关键包类型的日志
        let shouldLog = [.handshake, .handshakeAck, .heartbeat, .matrix].contains(packetToSend.type)
        if shouldLog {
            onLog?(
                "TX Packet: type=\(packetToSend.type) src=\(packetToSend.src) des=\(packetToSend.des)")
        }
        connection.send(content: encrypted, completion: .contentProcessed { _ in })
    }

    func sendClipboardHandshake(push: Bool) {
        var packet = MWBPacket()
        packet.type = push ? .clipboardPush : .clipboard
        packet.src = localId
        packet.des = peer?.id ?? 0
        packet.machineName = localName
        send(packet)
    }

    func appendClipboardChunk(_ payload: Data, isImage: Bool) {
        clipboardIsImage = isImage
        clipboardAccumulator.append(payload)
    }

    func consumeClipboardPayload() -> (data: Data, isImage: Bool)? {
        guard !clipboardAccumulator.isEmpty else { return nil }
        let data = clipboardAccumulator
        clipboardAccumulator = Data()
        return (data: data, isImage: clipboardIsImage)
    }

    func appendDragDropChunk(_ payload: Data) {
        dragDropAccumulator.append(payload)
    }

    func consumeDragDropPayload() -> Data? {
        guard !dragDropAccumulator.isEmpty else { return nil }
        let data = dragDropAccumulator
        dragDropAccumulator = Data()
        return data
    }

    private func sendHandshakeBurst() {
        var randomData = Data(count: MWBPacket.extendedSize)
        randomData.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            for i in 0 ..< buffer.count {
                base.storeBytes(of: UInt8.random(in: 0 ... 255), toByteOffset: i, as: UInt8.self)
            }
        }

        var packet = MWBPacket(data: randomData)
        packet.type = .handshake
        packet.src = localId
        packet.des = 0
        packet.machineName = localName
        handshakeChallenge = (packet.machine1, packet.machine2, packet.machine3, packet.machine4)
        handshakeAckFailures = 0

        onLog?("→ Sending handshake burst (10 packets)")
        for _ in 0 ..< 10 {
            send(packet)
        }
    }

    private func sendInitialIVBlock() {
        let random = Data((0 ..< 16).map { _ in UInt8.random(in: 0 ... 255) })
        if let encrypted = encrypt(random) {
            // 简化日志输出
            connection.send(content: encrypted, completion: .contentProcessed { _ in })
        }
    }

    func startHeartbeat(initial: Bool = false) {
        heartbeatTimer?.cancel()

        if initial {
            var initialPacket = MWBPacket()
            initialPacket.type = .heartbeatEx
            initialPacket.src = localId
            initialPacket.des = Int32(255)
            initialPacket.machineName = localName
            send(initialPacket)
        }

        heartbeatTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                var packet = MWBPacket()
                packet.type = .heartbeat
                packet.src = localId
                packet.des = Int32(255)
                packet.machineName = localName
                send(packet)
            }
        }
    }

    func cancelHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    func startClipboardBeat() {
        clipboardBeatTimer?.cancel()
        clipboardBeatTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                var packet = MWBPacket()
                packet.type = .clipboard
                packet.src = localId
                packet.des = Int32(255)
                packet.machineName = localName
                send(packet)
            }
        }
    }

    func sendHeartbeatAck() {
        var packet = MWBPacket()
        packet.type = .heartbeat
        packet.src = localId
        packet.des = Int32(255)
        packet.machineName = localName
        send(packet)
    }

    func sendHeartbeatExL3() {
        var packet = MWBPacket()
        packet.type = .heartbeatExL3
        packet.src = localId
        packet.des = Int32(255)
        packet.machineName = localName
        send(packet)
    }

    func cancelClipboardBeat() {
        clipboardBeatTimer?.cancel()
        clipboardBeatTimer = nil
    }

    func sendHelloBurst() {
        helloBurstTask?.cancel()
        helloBurstTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0 ..< 2 {
                var packet = MWBPacket()
                packet.type = .hello
                packet.src = localId
                packet.des = Int32(255)
                packet.machineName = localName
                send(packet)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func close() {
        cancelHeartbeat()
        cancelClipboardBeat()
        helloBurstTask?.cancel()
        helloBurstTask = nil
        connection.cancel()
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
            [weak self] content, _, isComplete, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let content {
                    // 减少日志频率，只在大包时输出
                    if content.count >= 256 {
                        onLog?("Received \(content.count) encrypted bytes")
                    }
                    encryptedBuffer.append(content)
                    decryptAvailable()
                    parsePackets()
                }
                if !isComplete {
                    receiveLoop()
                } else {
                    onDisconnected?()
                }
            }
        }
    }

    private func decryptAvailable() {
        while encryptedBuffer.count >= 16 {
            let chunk = encryptedBuffer.prefix(16)
            encryptedBuffer.removeFirst(16)
            if let decrypted = decrypt(chunk) {
                guard decrypted.count == 16 else {
                    MBLogger.network.error(
                        "MWB decrypt block size mismatch: \(decrypted.count, privacy: .public)")
                    continue
                }
                plainBuffer.append(decrypted)
            } else {
                MBLogger.network.error("MWB decrypt failed")
            }
        }

        if !initialBlockDiscarded, plainBuffer.count >= 16 {
            plainBuffer.removeFirst(16)
            initialBlockDiscarded = true
        }
    }

    private func parsePackets() {
        while plainBuffer.count >= MWBPacket.baseSize {
            guard let rawType = plainBuffer.first else { break }
            let isBig = MWBPacket.isBigType(rawType: rawType)
            let needed = isBig ? MWBPacket.extendedSize : MWBPacket.baseSize
            if plainBuffer.count < needed { break }

            let packetData = Data(plainBuffer.prefix(needed))
            plainBuffer.removeFirst(needed)
            var packet = MWBPacket(data: packetData)

            guard packet.data.count >= 4 else {
                onLog?(
                    "Packet too short for header: \(packet.data.count) bytes, rawType=\(rawType)")
                continue
            }

            guard packet.validate(magicNumber: crypto.magicNumber) else {
                let expected = (crypto.magicNumber >> 16) & 0xFFFF
                let msg =
                    "MWB packet rejected. Magic=\(packet.magicHigh16) Expected=\(expected) RawType=\(rawType) Len=\(packet.data.count)"
                MBLogger.network.debug("\(msg)")
                // Only log frequency to avoid spamming UI?
                // For diagnosis, let's log it once or periodically.
                if packet.magicHigh16 != 0 { // Don't log all zeros
                    onLog?(
                        "Packet Reject: Magic \(String(format: "%04X", packet.magicHigh16)) != \(String(format: "%04X", expected))")
                }
                continue
            }

            packet.data[1] = 0
            packet.data[2] = 0
            packet.data[3] = 0

            // 只输出重要的包类型日志
            let shouldLog = [
                .handshake, .handshakeAck, .heartbeat, .machineSwitched, .matrix,
                .captureScreenCommand,
            ].contains(packet.type)
            let suppressHandshakeLog =
                isHandshakeVerified && (packet.type == .handshake || packet.type == .handshakeAck)
            if shouldLog, !suppressHandshakeLog {
                onLog?("RX Packet: type=\(packet.type) src=\(packet.src) des=\(packet.des)")
            }
            onPacket?(packet)
        }
    }

    private func encrypt(_ data: Data) -> Data? {
        guard var encryptor else { return nil }
        let encrypted = encryptor.update(data)
        self.encryptor = encryptor
        return encrypted
    }

    private func decrypt(_ data: Data) -> Data? {
        guard var decryptor else { return nil }
        let decrypted = decryptor.update(data)
        self.decryptor = decryptor
        return decrypted
    }

    private func finalize(_ packet: MWBPacket) -> MWBPacket? {
        var packet = packet
        if packet.id == 0 {
            packetCounter &+= 1
            packet.id = packetCounter
        }
        packet.finalizeForSend(magicNumber: crypto.magicNumber)
        if packet.isBigPackage {
            packet.data = packet.data.prefix(MWBPacket.extendedSize)
        } else {
            packet.data = packet.data.prefix(MWBPacket.baseSize)
        }
        return packet
    }
}
