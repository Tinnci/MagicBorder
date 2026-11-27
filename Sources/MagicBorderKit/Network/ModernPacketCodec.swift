import CryptoKit
public import Foundation

/// Framing, JSON coding, AEAD frame encryption (AES-256-GCM), and HMAC authentication for Modern mode.
public final class ModernPacketCodec {
    public enum CodecError: Error, Equatable, Sendable {
        case frameTooLarge(Int)
        case emptyFrame
        case invalidHeader
        case authenticationFailed
    }

    public static let maxFrameLength = 32 * 1024 * 1024
    private static let encryptedMagic = Data([0x4D, 0x42, 0x47, 0x31])  // "MBG1"
    private static let kdfSalt = Data("MagicBorder-Modern-AEAD-v1".utf8)
    private static let kdfInfo = Data("frame-encryption".utf8)

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func encodeFrame(_ packet: PacketType, securityKey: String = "") throws -> Data {
        let json = try self.encoder.encode(packet)
        guard !json.isEmpty else { throw CodecError.emptyFrame }

        let wireBody: Data
        if !securityKey.isEmpty {
            let symmetricKey = Self.deriveAEADKey(from: securityKey)
            guard let sealed = try? AES.GCM.seal(json, using: symmetricKey),
                let combined = sealed.combined
            else {
                throw CodecError.authenticationFailed
            }
            var encrypted = Data(capacity: Self.encryptedMagic.count + combined.count)
            encrypted.append(Self.encryptedMagic)
            encrypted.append(combined)
            wireBody = encrypted
        } else {
            wireBody = json
        }

        guard wireBody.count <= Self.maxFrameLength else {
            throw CodecError.frameTooLarge(wireBody.count)
        }

        var length = UInt32(wireBody.count).littleEndian
        var frame = Data(capacity: 4 + wireBody.count)
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(wireBody)
        return frame
    }

    public func decodeLengthHeader(_ header: Data) -> Int? {
        guard header.count == 4 else { return nil }
        let raw = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let length = Int(UInt32(littleEndian: raw))
        guard length > 0, length <= Self.maxFrameLength else { return nil }
        return length
    }

    public func decodePacket(_ payload: Data, securityKey: String = "") throws -> PacketType {
        let plaintext: Data
        if !securityKey.isEmpty {
            guard payload.count > Self.encryptedMagic.count,
                payload.starts(with: Self.encryptedMagic)
            else {
                throw CodecError.authenticationFailed
            }
            let combined = Data(payload.dropFirst(Self.encryptedMagic.count))
            let symmetricKey = Self.deriveAEADKey(from: securityKey)
            do {
                let sealedBox = try AES.GCM.SealedBox(combined: combined)
                plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)
            } catch {
                throw CodecError.authenticationFailed
            }
        } else {
            if payload.starts(with: Self.encryptedMagic) {
                throw CodecError.authenticationFailed
            }
            plaintext = payload
        }

        return try self.decoder.decode(PacketType.self, from: plaintext)
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

    private static func deriveAEADKey(from securityKey: String) -> SymmetricKey {
        let inputMaterial = SymmetricKey(data: Data(securityKey.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputMaterial,
            salt: Self.kdfSalt,
            info: Self.kdfInfo,
            outputByteCount: 32)
    }
}
