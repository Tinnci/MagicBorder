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
