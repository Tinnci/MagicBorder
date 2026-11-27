import CryptoKit
public import Foundation

/// Framing, JSON coding, and constant-time HMAC authentication for the Modern protocol.
public final class ModernPacketCodec {
    public enum CodecError: Error, Equatable, Sendable {
        case frameTooLarge(Int)
        case emptyFrame
        case invalidHeader
    }

    public static let maxFrameLength = 32 * 1024 * 1024

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func encodeFrame(_ packet: PacketType) throws -> Data {
        let payload = try self.encoder.encode(packet)
        guard !payload.isEmpty else { throw CodecError.emptyFrame }
        guard payload.count <= Self.maxFrameLength else {
            throw CodecError.frameTooLarge(payload.count)
        }

        var length = UInt32(payload.count).littleEndian
        var frame = Data(capacity: 4 + payload.count)
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(payload)
        return frame
    }

    public func decodeLengthHeader(_ header: Data) -> Int? {
        guard header.count == 4 else { return nil }
        let raw = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let length = Int(UInt32(littleEndian: raw))
        guard length > 0, length <= Self.maxFrameLength else { return nil }
        return length
    }

    public func decodePacket(_ payload: Data) throws -> PacketType {
        try self.decoder.decode(PacketType.self, from: payload)
    }

    public static func sign(machineID: UUID, securityKey: String) -> String? {
        guard !securityKey.isEmpty,
            let keyData = securityKey.data(using: .utf8),
            let idData = machineID.uuidString.data(using: .utf8)
        else { return nil }

        let key = SymmetricKey(data: keyData)
        let signature = HMAC<SHA256>.authenticationCode(for: idData, using: key)
        return Data(signature).base64EncodedString()
    }

    public static func verify(signature: String?, machineID: UUID, securityKey: String) -> Bool {
        guard !securityKey.isEmpty else { return true }
        guard let signature,
            let sigData = Data(base64Encoded: signature),
            let keyData = securityKey.data(using: .utf8),
            let idData = machineID.uuidString.data(using: .utf8)
        else { return false }

        let key = SymmetricKey(data: keyData)
        return HMAC<SHA256>.isValidAuthenticationCode(sigData, authenticating: idData, using: key)
    }
}
