import Foundation
import Testing

@testable import MagicBorderKit

@Suite("ModernPacketCodec")
struct ModernPacketCodecTests {
    @Test func frameEncodeAndDecodeRoundTrip() throws {
        let codec = ModernPacketCodec()
        let machineID = UUID()
        let info = MachineInfo(
            id: machineID,
            name: "Mac Studio",
            screenWidth: 2560,
            screenHeight: 1440,
            signature: ModernPacketCodec.sign(machineID: machineID, securityKey: "shared-secret"))

        let frame = try codec.encodeFrame(.handshake(info: info))
        let header = frame.prefix(4)
        let length = try #require(codec.decodeLengthHeader(Data(header)))
        #expect(length == frame.count - 4)

        let decoded = try codec.decodePacket(frame.dropFirst(4))
        guard case .handshake(let decodedInfo) = decoded else {
            Issue.record("Expected handshake packet")
            return
        }
        #expect(decodedInfo == info)
    }

    @Test func encryptedFrameRoundTripsAndRejectsTamperingOrDowngrade() throws {
        let codec = ModernPacketCodec()
        let key = "StrongSharedKey2026!"
        let secretMessage = "ConfidentialClipboardPayload"
        let packet = PacketType.clipboardData(
            ClipboardPayload(content: Data(secretMessage.utf8), type: .text))

        let encryptedFrame = try codec.encodeFrame(packet, securityKey: key)
        let length = try #require(codec.decodeLengthHeader(Data(encryptedFrame.prefix(4))))
        let body = Data(encryptedFrame.dropFirst(4))
        #expect(length == body.count)
        #expect(body.starts(with: Data("MBG1".utf8)))

        // Wire payload must not leak plaintext JSON or secret text.
        let wireText = String(decoding: body, as: UTF8.self)
        #expect(!wireText.contains(secretMessage))

        let decoded = try codec.decodePacket(body, securityKey: key)
        guard case .clipboardData(let payload) = decoded else {
            Issue.record("Expected clipboardData packet")
            return
        }
        #expect(String(data: payload.content, encoding: .utf8) == secretMessage)

        // Wrong key fails AEAD authentication.
        #expect(throws: ModernPacketCodec.CodecError.authenticationFailed) {
            try codec.decodePacket(body, securityKey: "WrongKey!")
        }

        // Empty key rejects encrypted frames.
        #expect(throws: ModernPacketCodec.CodecError.authenticationFailed) {
            try codec.decodePacket(body, securityKey: "")
        }

        // Tampered ciphertext fails AEAD authentication.
        var tampered = body
        tampered[tampered.count - 1] ^= 0xFF
        #expect(throws: ModernPacketCodec.CodecError.authenticationFailed) {
            try codec.decodePacket(tampered, securityKey: key)
        }

        // Plaintext downgrade frame is rejected when a key is configured.
        let plaintextFrame = try codec.encodeFrame(packet, securityKey: "")
        #expect(throws: ModernPacketCodec.CodecError.authenticationFailed) {
            try codec.decodePacket(Data(plaintextFrame.dropFirst(4)), securityKey: key)
        }
    }

    @Test func decodeLengthHeaderRejectsZeroAndOversizedFrames() {
        let codec = ModernPacketCodec()

        var zero = UInt32(0).littleEndian
        let zeroData = withUnsafeBytes(of: &zero) { Data($0) }
        #expect(codec.decodeLengthHeader(zeroData) == nil)

        var oversized = UInt32(ModernPacketCodec.maxFrameLength + 1).littleEndian
        let oversizedData = withUnsafeBytes(of: &oversized) { Data($0) }
        #expect(codec.decodeLengthHeader(oversizedData) == nil)

        #expect(codec.decodeLengthHeader(Data([1, 2])) == nil)
    }

    @Test func hmacVerifyRejectsNilOrTamperedSignatureWhenKeyIsSet() throws {
        let id = UUID()
        let key = "SecretKey12345678"
        let signature = try #require(ModernPacketCodec.sign(machineID: id, securityKey: key))

        #expect(ModernPacketCodec.verify(signature: signature, machineID: id, securityKey: key))
        #expect(!ModernPacketCodec.verify(signature: nil, machineID: id, securityKey: key))
        #expect(!ModernPacketCodec.verify(signature: "not-base64!", machineID: id, securityKey: key))
        #expect(!ModernPacketCodec.verify(signature: signature, machineID: UUID(), securityKey: key))
        #expect(!ModernPacketCodec.verify(signature: signature, machineID: id, securityKey: "WrongKey"))
        #expect(ModernPacketCodec.verify(signature: nil, machineID: id, securityKey: ""))
    }
}
