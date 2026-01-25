import CryptoKit
import Foundation

public enum MWBPacketType: UInt8 {
    case invalid = 0xFF
    case heartbeat = 20
    case hello = 3
    case byeBye = 4
    case keyboard = 122
    case mouse = 123
    case handshake = 126
    case handshakeAck = 127
    // Add others as needed
}

public struct MWBPacket {
    /// Raw data storage (Fixed 64 bytes to accommodate all cases)
    public var data: Data

    public init() {
        self.data = Data(count: 64)
    }

    public init(data: Data) {
        self.data = data
        if self.data.count < 64 {
            // Padding to 64 bytes
            self.data.append(Data(count: 64 - self.data.count))
        }
    }

    // MARK: - Header (0-3)

    public var type: MWBPacketType {
        get { MWBPacketType(rawValue: data[0]) ?? .invalid }
        set { data[0] = newValue.rawValue }
    }

    public var checksum: UInt8 {
        get { data[1] }
        set { data[1] = newValue }
    }

    // Magic Number occupies data[2] and data[3]
    public var magic: UInt16 {
        get { data.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self) } }
        set {
            var val = newValue
            let bytes = Data(bytes: &val, count: 2)
            data[2] = bytes[0]
            data[3] = bytes[1]
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

    // MARK: - Payload (24-31) [Union Area]

    // Mouse Mode
    public var x: Int32 {
        get { getInt32(at: 24) }
        set { setInt32(newValue, at: 24) }
    }

    public var y: Int32 {
        get { getInt32(at: 28) }
        set { setInt32(newValue, at: 28) }
    }

    // Keyboard Mode (Memory reuse)
    public var key: Int32 {
        get { getInt32(at: 24) }
        set { setInt32(newValue, at: 24) }
    }

    // MARK: - Extended (32+)

    public var wheel: Int32 {
        get { getInt32(at: 32) }
        set { setInt32(newValue, at: 32) }
    }

    // MARK: - Helpers

    private func getInt32(at offset: Int) -> Int32 {
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int32.self) }
    }

    private mutating func setInt32(_ value: Int32, at offset: Int) {
        var val = value
        let bytes = Data(bytes: &val, count: 4)
        data.replaceSubrange(offset..<offset + 4, with: bytes)
    }

    /// Prepare for sending: Calculate checksum and fill Magic
    public mutating func finalizeForSend(magicNumber: UInt32) {
        // 1. Set Magic (Take high 16 bits of MagicNumber)
        // C# Logic: bytes[3] = (magic >> 24), bytes[2] = (magic >> 16)
        data[3] = UInt8((magicNumber >> 24) & 0xFF)
        data[2] = UInt8((magicNumber >> 16) & 0xFF)

        // 2. Clear Checksum for calculation
        data[1] = 0

        // 3. Calculate Checksum (Byte 2 to End)
        let endIndex = isBigPackage ? 64 : 32
        var sum: UInt8 = 0
        for i in 2..<endIndex {
            sum = sum &+ data[i]  // &+ is Swift overflow operator
        }
        data[1] = sum
    }

    var isBigPackage: Bool {
        if type == .invalid { return false }
        // For initial version, stick to 32 bytes unless extended features needed
        return false
    }
}
