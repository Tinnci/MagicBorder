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

    public init(localName: String, localId: Int32, messagePort: UInt16 = 15101, clipboardPort: UInt16 = 15100) {
        self.localName = localName
        self.localId = localId
        self.messagePort = messagePort
        self.clipboardPort = clipboardPort
    }

    public func start(securityKey: String) {
        currentSecurityKey = securityKey
        crypto.deriveKey(from: securityKey)
        startMessageListener()
        startClipboardListener()
    }

    public func stop() {
        messageListener?.cancel()
        clipboardListener?.cancel()
        messageListener = nil
        clipboardListener = nil
        messageSessions.removeAll()
        clipboardSessions.removeAll()
    }

    public func updateSecurityKey(_ key: String) {
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
        let host = NWEndpoint.Host(ip)

        if let port = NWEndpoint.Port(rawValue: messagePort ?? self.messagePort) {
            let connection = NWConnection(to: .hostPort(host: host, port: port), using: .tcp)
            handleNewConnection(connection, kind: .message)
        }

        if let port = NWEndpoint.Port(rawValue: clipboardPort ?? self.clipboardPort) {
            let connection = NWConnection(to: .hostPort(host: host, port: port), using: .tcp)
            handleNewConnection(connection, kind: .clipboard)
        }
    }

    public func sendMachineMatrix(_ machines: [String], twoRow: Bool = false, swap: Bool = false) {
        guard !messageSessions.isEmpty else { return }
        var packet = MWBPacket()
        let flags: UInt8 = (swap ? 0x02 : 0x00) | (twoRow ? 0x04 : 0x00)
        packet.rawType = MWBPacketType.matrix.rawValue | flags
        packet.src = localId
        packet.des = Int32(255)
        packet.machineName = machines.joined(separator: ",")
        broadcast(packet, to: messageSessions)
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
        guard let target = clipboardTargets().first(where: { $0.peer?.id == peerId })
            ?? messageSessions.first(where: { $0.peer?.id == peerId }) else { return }
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
           let png = bitmap.representation(using: .png, properties: [:]) {
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
                print("MWBCompatibility: invalid message port: \(messagePort)")
                return
            }
            let listener = try NWListener(using: .tcp, on: port)
            self.messageListener = listener
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection, kind: .message)
                }
            }
            listener.start(queue: DispatchQueue.main)
        } catch {
            print("MWBCompatibility: failed to start message listener: \(error)")
        }
    }

    private func startClipboardListener() {
        do {
            guard let port = NWEndpoint.Port(rawValue: clipboardPort) else {
                print("MWBCompatibility: invalid clipboard port: \(clipboardPort)")
                return
            }
            let listener = try NWListener(using: .tcp, on: port)
            self.clipboardListener = listener
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection, kind: .clipboard)
                }
            }
            listener.start(queue: DispatchQueue.main)
        } catch {
            print("MWBCompatibility: failed to start clipboard listener: \(error)")
        }
    }

    private func handleNewConnection(_ connection: NWConnection, kind: MWBSessionKind) {
        guard crypto.sessionKey != nil else {
            connection.cancel()
            return
        }

        let session = MWBSession(
            connection: connection,
            kind: kind,
            crypto: crypto,
            localName: localName,
            localId: localId
        )

        session.onPacket = { [weak self, weak session] packet in
            guard let self, let session else { return }
            self.handlePacket(packet, from: session)
        }

        session.onDisconnected = { [weak self, weak session] in
            guard let self, let session else { return }
            self.removeSession(session)
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
        messageSessions.removeAll { $0 === session }
        clipboardSessions.removeAll { $0 === session }
        if let peer = session.peer {
            onDisconnected?(peer)
        }
    }

    private func handlePacket(_ packet: MWBPacket, from session: MWBSession) {
        switch packet.type {
        case .handshake:
            session.peer = MWBPeer(id: packet.src, name: packet.machineName)
            if let peer = session.peer {
                onConnected?(peer)
            }
            session.sendHandshakeAck()
        case .handshakeAck:
            session.peer = MWBPeer(id: packet.src, name: packet.machineName)
            if let peer = session.peer {
                onConnected?(peer)
            }
        case .hello, .hi, .awake, .heartbeat, .heartbeatEx, .heartbeatExL2, .heartbeatExL3:
            if session.peer == nil {
                session.peer = MWBPeer(id: packet.src, name: packet.machineName)
            }
            if let peer = session.peer {
                onConnected?(peer)
            }
        case .byeBye:
            if let peer = session.peer {
                onDisconnected?(peer)
            }
        case .clipboard, .clipboardPush:
            if session.kind == .clipboard {
                session.peer = MWBPeer(id: packet.src, name: packet.machineName)
                if let peer = session.peer {
                    onConnected?(peer)
                }
                session.sendClipboardHandshake(push: packet.type == .clipboardPush)
            }
        case .mouse:
            let event = MWBMouseEvent(x: packet.mouseX, y: packet.mouseY, wheel: packet.mouseWheel, flags: packet.mouseFlags)
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
               let urls = decodeFileDrop(payload) {
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
            let matrix = packet.machineName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
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
              let compressed = MWBCompression.deflateCompress(textData) else { return }
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
            let chunk = data.subdata(in: index..<end)
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
        let paths = urls.map { $0.path }
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

    var peer: MWBPeer?

    var onPacket: ((MWBPacket) -> Void)?
    var onDisconnected: (() -> Void)?

    private var encryptor: MWBStreamCipher?
    private var decryptor: MWBStreamCipher?

    private var encryptedBuffer = Data()
    private var plainBuffer = Data()
    private var initialBlockDiscarded = false

    private var clipboardAccumulator = Data()
    private var clipboardIsImage = false
    private var dragDropAccumulator = Data()

    init(connection: NWConnection, kind: MWBSessionKind, crypto: MWBCrypto, localName: String, localId: Int32) {
        self.connection = connection
        self.kind = kind
        self.crypto = crypto
        self.localName = localName
        self.localId = localId
        self.encryptor = crypto.makeEncryptor()
        self.decryptor = crypto.makeDecryptor()
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.sendInitialIVBlock()
                    if self.kind == .message {
                        self.sendHandshakeBurst()
                    }
                    self.receiveLoop()
                case .failed, .cancelled:
                    self.onDisconnected?()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    func send(_ packet: MWBPacket) {
          guard let packetToSend = finalize(packet),
              let encrypted = encrypt(packetToSend.data) else { return }

        connection.send(content: encrypted, completion: .contentProcessed { _ in })
    }

    func sendHandshakeAck() {
        var packet = MWBPacket()
        packet.type = .handshakeAck
        packet.src = localId
        packet.des = peer?.id ?? 0
        packet.machineName = localName
        send(packet)
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
        for _ in 0..<10 {
            var packet = MWBPacket()
            packet.type = .handshake
            packet.src = localId
            packet.des = 0
            packet.machineName = localName
            send(packet)
        }
    }

    private func sendInitialIVBlock() {
        let random = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        if let encrypted = encrypt(random) {
            connection.send(content: encrypted, completion: .contentProcessed { _ in })
        }
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, isComplete, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let content {
                    self.encryptedBuffer.append(content)
                    self.decryptAvailable()
                    self.parsePackets()
                }
                if !isComplete {
                    self.receiveLoop()
                } else {
                    self.onDisconnected?()
                }
            }
        }
    }

    private func decryptAvailable() {
        while encryptedBuffer.count >= 16 {
            let chunk = encryptedBuffer.prefix(16)
            encryptedBuffer.removeFirst(16)
            if let decrypted = decrypt(chunk) {
                plainBuffer.append(decrypted)
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

            let packetData = plainBuffer.prefix(needed)
            plainBuffer.removeFirst(needed)
            var packet = MWBPacket(data: packetData)

            guard packet.validate(magicNumber: crypto.magicNumber) else { continue }

            packet.data[1] = 0
            packet.data[2] = 0
            packet.data[3] = 0

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
        packet.finalizeForSend(magicNumber: crypto.magicNumber)
        if packet.isBigPackage {
            packet.data = packet.data.prefix(MWBPacket.extendedSize)
        } else {
            packet.data = packet.data.prefix(MWBPacket.baseSize)
        }
        return packet
    }
}
