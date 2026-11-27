import Foundation
import Testing

@testable import MagicBorderKit

@Suite("MWBProtocol")
struct MWBProtocolTests {
    @Test func finalizeAndValidateRoundTripsBaseAndExtendedPackets() {
        let magic: UInt32 = 0xABCD_1234

        var mousePacket = MWBPacket()
        mousePacket.type = .mouse
        mousePacket.id = 77
        mousePacket.src = 1234
        mousePacket.des = 255
        mousePacket.mouseX = 32767
        mousePacket.mouseY = 16384
        mousePacket.mouseWheel = -120
        mousePacket.mouseFlags = 0x20A
        mousePacket.finalizeForSend(magicNumber: magic)

        #expect(!mousePacket.isBigPackage)
        #expect(mousePacket.validate(magicNumber: magic))
        #expect(mousePacket.mouseX == 32767)
        #expect(mousePacket.mouseY == 16384)
        #expect(mousePacket.mouseWheel == -120)
        #expect(mousePacket.mouseFlags == 0x20A)

        var handshakePacket = MWBPacket()
        handshakePacket.type = .handshake
        handshakePacket.src = 42
        handshakePacket.machineName = "WORKSTATION-WIN"
        handshakePacket.finalizeForSend(magicNumber: magic)

        #expect(handshakePacket.isBigPackage)
        #expect(handshakePacket.validate(magicNumber: magic))
        #expect(handshakePacket.machineName == "WORKSTATION-WIN")
    }

    @Test func validationRejectsCorruptedChecksumOrMagic() {
        let magic: UInt32 = 0xCAFE_0000
        var packet = MWBPacket()
        packet.type = .heartbeat
        packet.src = 99
        packet.finalizeForSend(magicNumber: magic)
        #expect(packet.validate(magicNumber: magic))

        var wrongMagic = packet
        #expect(!wrongMagic.validate(magicNumber: 0xBEEF_0000))

        wrongMagic.data[1] &+= 1
        #expect(!wrongMagic.validate(magicNumber: magic))
    }

    @Test func matrixFlagsPreserveTwoRowAndSwapBits() {
        var packet = MWBPacket()
        packet.rawType = MWBPacketType.matrix.rawValue | 0x06

        #expect(packet.type == .matrix)
        #expect(packet.isMatrixPacket)
        #expect(packet.isBigPackage)
        #expect(MWBPacket.isBigType(rawType: packet.rawType))
    }

    @Test func littleEndianUnalignedReadWriteHandlesNegativeAndLargeValues() {
        var packet = MWBPacket()
        packet.timeStamp = -9_876_543_210_123
        #expect(packet.timeStamp == -9_876_543_210_123)

        packet.src = -42
        packet.des = 0x0102_0304
        #expect(packet.src == -42)
        #expect(packet.des == 0x0102_0304)
    }
}
