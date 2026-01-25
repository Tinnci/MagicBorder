import Foundation

public enum MWBPacketType: UInt8 {
    case invalid = 0xFF
    case error = 0xFE

    case hi = 2
    case hello = 3
    case byeBye = 4

    case heartbeat = 20
    case awake = 21
    case hideMouse = 50
    case heartbeatEx = 51
    case heartbeatExL2 = 52
    case heartbeatExL3 = 53

    case clipboard = 69
    case clipboardDragDrop = 70
    case clipboardDragDropEnd = 71
    case explorerDragDrop = 72
    case clipboardCapture = 73
    case captureScreenCommand = 74
    case clipboardDragDropOperation = 75
    case clipboardDataEnd = 76
    case machineSwitched = 77
    case clipboardAsk = 78
    case clipboardPush = 79

    case nextMachine = 121
    case keyboard = 122
    case mouse = 123
    case clipboardText = 124
    case clipboardImage = 125

    case handshake = 126
    case handshakeAck = 127

    case matrix = 128
}

public struct MWBPacket {
    public static let baseSize = 32
    public static let extendedSize = 64

    /// Raw data storage (Fixed 64 bytes to accommodate all cases)
    public var data: Data

    public init() {
        self.data = Data(count: MWBPacket.extendedSize)
    }

    public init(data: Data) {
        self.data = data
        if self.data.count < MWBPacket.extendedSize {
            self.data.append(Data(count: MWBPacket.extendedSize - self.data.count))
        }
    }

    // MARK: - Header (0-3)

    public var rawType: UInt8 {
        get { data[0] }
        set { data[0] = newValue }
    }

    public var type: MWBPacketType {
        get {
            if (rawType & MWBPacketType.matrix.rawValue) == MWBPacketType.matrix.rawValue {
                return .matrix
            }
            return MWBPacketType(rawValue: rawType) ?? .invalid
        }
        set { rawType = newValue.rawValue }
    }

    public var checksum: UInt8 {
        get { data[1] }
        set { data[1] = newValue }
    }

    // Magic Number occupies data[2] and data[3]
    public var magicHigh16: UInt16 {
        get {
            guard data.count >= 4 else { return 0 }
            return data.withUnsafeBytes { raw -> UInt16 in
                guard let base = raw.baseAddress else { return 0 }
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                let b2 = UInt16(bytes[2])
                let b3 = UInt16(bytes[3])
                return (b3 << 8) | b2
            }
        }
        set {
            if data.count < 4 { return }
            data[2] = UInt8(newValue & 0xFF)
            data[3] = UInt8((newValue >> 8) & 0xFF)
        }
    }

    // MARK: - Routing (4-15)

    public var id: Int32 {
        get { getInt32(at: 4) }
        set { setInt32(newValue, at: 4) }
    }

    public var src: Int32 {
        get { getInt32(at: 8) }
        set { setInt32(newValue, at: 8) }
    }

    public var des: Int32 {
        get { getInt32(at: 12) }
        set { setInt32(newValue, at: 12) }
    }

    // MARK: - Payload (16-31) [Union Area]

    public var timeStamp: Int64 {
        get { getInt64(at: 16) }
        set { setInt64(newValue, at: 16) }
    }

    // Mouse Mode (MOUSEDATA)
    public var mouseX: Int32 {
        get { getInt32(at: 16) }
        set { setInt32(newValue, at: 16) }
    }

    public var mouseY: Int32 {
        get { getInt32(at: 20) }
        set { setInt32(newValue, at: 20) }
    }

    public var mouseWheel: Int32 {
        get { getInt32(at: 24) }
        set { setInt32(newValue, at: 24) }
    }

    public var mouseFlags: Int32 {
        get { getInt32(at: 28) }
        set { setInt32(newValue, at: 28) }
    }

    // Keyboard Mode (KEYBDDATA)
    public var keyCode: Int32 {
        get { getInt32(at: 16) }
        set { setInt32(newValue, at: 16) }
    }

    public var keyFlags: Int32 {
        get { getInt32(at: 20) }
        set { setInt32(newValue, at: 20) }
    }

    // Machine IDs / Matrix data (overlaps)
    public var machine1: Int32 {
        get { getInt32(at: 16) }
        set { setInt32(newValue, at: 16) }
    }

    public var machine2: Int32 {
        get { getInt32(at: 20) }
        set { setInt32(newValue, at: 20) }
    }

    public var machine3: Int32 {
        get { getInt32(at: 32) }
        set { setInt32(newValue, at: 32) }
    }

    public var machine4: Int32 {
        get { getInt32(at: 36) }
        set { setInt32(newValue, at: 36) }
    }

    // Clipboard payload (last 48 bytes of extended packet)
    public var clipboardPayload: Data {
        get {
            let start = MWBPacket.extendedSize - 48
            return data.subdata(in: start..<MWBPacket.extendedSize)
        }
        set {
            let start = MWBPacket.extendedSize - 48
            var payload = newValue
            if payload.count < 48 {
                payload.append(Data(count: 48 - payload.count))
            }
            data.replaceSubrange(start..<MWBPacket.extendedSize, with: payload.prefix(48))
        }
    }

    // Machine name is ASCII, 32 bytes at offset 32 (big packet only)
    public var machineName: String {
        get {
            let nameData = data.subdata(in: 32..<64)
            return String(bytes: nameData, encoding: .ascii)?.trimmingCharacters(
                in: .whitespacesAndNewlines) ?? ""
        }
        set {
            var bytes = Data(
                newValue.padding(toLength: 32, withPad: " ", startingAt: 0).data(using: .ascii)
                    ?? Data())
            if bytes.count > 32 {
                bytes = bytes.prefix(32)
            } else if bytes.count < 32 {
                bytes.append(Data(count: 32 - bytes.count))
            }
            data.replaceSubrange(32..<64, with: bytes)
        }
    }

    // MARK: - Helpers

    private func getInt32(at offset: Int) -> Int32 {
        guard data.count >= offset + 4 else { return 0 }
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int32.self) }
    }

    private mutating func setInt32(_ value: Int32, at offset: Int) {
        // Ensure data is large enough
        if data.count < offset + 4 {
            if data.count < MWBPacket.extendedSize {
                data.append(Data(count: MWBPacket.extendedSize - data.count))
            }
            // Re-check
            if data.count < offset + 4 { return }
        }
        var val = value
        let bytes = Data(bytes: &val, count: 4)
        data.replaceSubrange(offset..<offset + 4, with: bytes)
    }

    private func getInt64(at offset: Int) -> Int64 {
        guard data.count >= offset + 8 else { return 0 }
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int64.self) }
    }

    private mutating func setInt64(_ value: Int64, at offset: Int) {
        if data.count < offset + 8 {
            if data.count < MWBPacket.extendedSize {
                data.append(Data(count: MWBPacket.extendedSize - data.count))
            }
            if data.count < offset + 8 { return }
        }
        var val = value
        let bytes = Data(bytes: &val, count: 8)
        data.replaceSubrange(offset..<offset + 8, with: bytes)
    }

    public var isMatrixPacket: Bool {
        guard !data.isEmpty else { return false }
        return (rawType & MWBPacketType.matrix.rawValue) == MWBPacketType.matrix.rawValue
    }

    public var isBigPackage: Bool {
        if type == .invalid { return false }
        if isMatrixPacket { return true }
        switch type {
        case .hello, .awake, .heartbeat, .heartbeatEx, .handshake, .handshakeAck, .clipboardPush,
            .clipboard, .clipboardAsk, .clipboardImage, .clipboardText, .clipboardDataEnd:
            return true
        default:
            return false
        }
    }

    public static func isBigType(rawType: UInt8) -> Bool {
        if (rawType & MWBPacketType.matrix.rawValue) == MWBPacketType.matrix.rawValue {
            return true
        }
        switch MWBPacketType(rawValue: rawType) ?? .invalid {
        case .hello, .awake, .heartbeat, .heartbeatEx, .handshake, .handshakeAck, .clipboardPush,
            .clipboard, .clipboardAsk, .clipboardImage, .clipboardText, .clipboardDataEnd:
            return true
        default:
            return false
        }
    }

    /// Prepare for sending: Calculate checksum and fill Magic
    public mutating func finalizeForSend(magicNumber: UInt32) {
        // bytes[3] = (magic >> 24), bytes[2] = (magic >> 16)
        data[3] = UInt8((magicNumber >> 24) & 0xFF)
        data[2] = UInt8((magicNumber >> 16) & 0xFF)

        // Clear checksum for calculation
        data[1] = 0

        let endIndex = isBigPackage ? MWBPacket.extendedSize : MWBPacket.baseSize
        var sum: UInt8 = 0
        for i in 2..<endIndex {
            sum = sum &+ data[i]
        }
        data[1] = sum
    }

    public func validate(magicNumber: UInt32) -> Bool {
        guard data.count >= MWBPacket.baseSize else { return false }

        let expected = UInt16((magicNumber >> 16) & 0xFFFF)
        var b2: UInt8 = 0
        var b3: UInt8 = 0
        let headerOK = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress, raw.count >= 4 else { return false }
            b2 = base.load(fromByteOffset: 2, as: UInt8.self)
            b3 = base.load(fromByteOffset: 3, as: UInt8.self)
            return true
        }
        guard headerOK else { return false }
        let actual = UInt16((UInt16(b3) << 8) | UInt16(b2))
        if actual != expected {
            return false
        }

        let endIndex = isBigPackage ? MWBPacket.extendedSize : MWBPacket.baseSize
        guard data.count >= endIndex else { return false }
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            var sum: UInt8 = 0
            for i in 2..<endIndex {
                sum = sum &+ bytes[i]
            }
            return bytes[1] == sum
        }
    }
}
