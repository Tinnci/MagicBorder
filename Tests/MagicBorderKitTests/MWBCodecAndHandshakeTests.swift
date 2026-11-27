import Foundation
import Testing

@testable import MagicBorderKit

@Suite("MWBCodecAndHandshake")
struct MWBCodecAndHandshakeTests {
    @Test func streamFramerHandlesIVDiscardFragmentationAndCoalescing() throws {
        let material = try #require(MWBKeyDerivation.derive(from: "MagicBorderTestKey16"))
        let sender = MWBStreamFramer(crypto: material)
        let receiver = MWBStreamFramer(crypto: material)
        defer {
            sender.close()
            receiver.close()
        }

        let ivBlock = try #require(sender.makeInitialIVBlock())
        var mouse = MWBPacket()
        mouse.type = .mouse
        mouse.src = 10
        mouse.mouseX = 1234
        mouse.mouseY = 5678

        var handshake = MWBPacket()
        handshake.type = .handshake
        handshake.src = 10
        handshake.machineName = "MACBOOK"

        let encodedMouse = try #require(sender.encodeForSend(mouse))
        let encodedHandshake = try #require(sender.encodeForSend(handshake))

        let streamBytes = ivBlock + encodedMouse.encrypted + encodedHandshake.encrypted

        // Feed fragmented chunks (7 bytes at a time) to exercise block buffering and offset compaction.
        var parsedPackets: [MWBPacket] = []
        var cursor = 0
        while cursor < streamBytes.count {
            let next = min(cursor + 7, streamBytes.count)
            let result = receiver.receiveEncrypted(streamBytes.subdata(in: cursor..<next))
            #expect(result.rejected.isEmpty)
            parsedPackets.append(contentsOf: result.packets)
            cursor = next
        }

        #expect(parsedPackets.count == 2)
        #expect(parsedPackets[0].type == .mouse)
        #expect(parsedPackets[0].mouseX == 1234)
        #expect(parsedPackets[0].mouseY == 5678)
        #expect(parsedPackets[1].type == .handshake)
        #expect(parsedPackets[1].machineName == "MACBOOK")
    }

    @Test func streamFramerReportsRejectedMagic() throws {
        let senderMaterial = try #require(MWBKeyDerivation.derive(from: "KeyAlpha1234567890"))
        let receiverMaterial = try #require(MWBKeyDerivation.derive(from: "KeyBravo1234567890"))
        let sender = MWBStreamFramer(crypto: senderMaterial)
        let receiver = MWBStreamFramer(crypto: receiverMaterial)
        defer {
            sender.close()
            receiver.close()
        }

        let iv = try #require(sender.makeInitialIVBlock())
        var packet = MWBPacket()
        packet.type = .heartbeat
        let encoded = try #require(sender.encodeForSend(packet))

        let result = receiver.receiveEncrypted(iv + encoded.encrypted)
        #expect(result.packets.isEmpty)
        #expect(!result.rejected.isEmpty)
    }

    @Test func clipboardCodecRoundTripsTextFilesAndMatrix() throws {
        let compressed = try #require(MWBClipboardCodec.encodeClipboardText("Hello MWB"))
        #expect(MWBClipboardCodec.decodeClipboardText(compressed) == "Hello MWB")

        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.png")]
        let filePayload = MWBClipboardCodec.encodeFileDrop(urls)
        #expect(MWBClipboardCodec.decodeFileDrop(filePayload) == urls)

        let chunks = MWBClipboardCodec.chunkPackets(
            type: .clipboardText, data: Data(repeating: 0x5A, count: 100), localId: 7)
        #expect(chunks.count == 3)
        #expect(chunks.allSatisfy { $0.src == 7 && $0.type == .clipboardText })

        let matrixPackets = MWBClipboardCodec.encodeMatrixPackets(machines: ["MAC", "WIN"], twoRow: true, swap: true)
        #expect(matrixPackets.count == 4)
        #expect(matrixPackets[0].machineName == "MAC")
        #expect(matrixPackets[1].machineName == "WIN")
        #expect(matrixPackets[3].src == 4)
        let decoded = MWBClipboardCodec.decodeMatrixPacket(matrixPackets[0])
        #expect(decoded.names == ["MAC"])
        #expect(decoded.twoRow)
        #expect(decoded.swap)
    }

    @Test func handshakeStateMachineVerifiesBitwiseNotChallenge() throws {
        var initiator = MWBHandshakeStateMachine()
        let responder = MWBHandshakeStateMachine()

        let burst = initiator.makeOutboundHandshakeBurst(localId: 101, localName: "MAC", count: 3)
        #expect(burst.count == 3)

        var badAck = try #require(burst.first)
        badAck.type = .handshakeAck
        #expect(initiator.processAck(badAck) == .failedFirstTime)
        #expect(initiator.processAck(badAck) == .ignored)

        var goodAck = responder.makeHandshakeAck(for: try #require(burst.first), localName: "WIN")
        goodAck.src = 202
        let outcome = initiator.processAck(goodAck)
        #expect(outcome == .verified(MWBPeer(id: 202, name: "WIN")))
        #expect(initiator.isVerified)
    }

    @Test func reconnectPolicyEnforcesSuppressionAndMaxAttempts() {
        var policy = MWBReconnectPolicy(maxAttempts: 2)
        policy.recordConnectTarget(host: "192.168.1.50", messagePort: 15101, clipboardPort: 15100)

        let dummyA = NSObject()
        let dummyB = NSObject()
        policy.suppressReconnect(for: ObjectIdentifier(dummyA))

        #expect(
            policy.evaluateDisconnect(
                sessionID: ObjectIdentifier(dummyA),
                isOutbound: true,
                kind: .message,
                remainingMessageSessions: 0) == .skip)

        #expect(
            policy.evaluateDisconnect(
                sessionID: ObjectIdentifier(dummyB),
                isOutbound: true,
                kind: .message,
                remainingMessageSessions: 0)
                == .schedule(host: "192.168.1.50", messagePort: 15101, clipboardPort: 15100, attempt: 1))

        #expect(
            policy.evaluateDisconnect(
                sessionID: ObjectIdentifier(dummyB),
                isOutbound: true,
                kind: .message,
                remainingMessageSessions: 0)
                == .schedule(host: "192.168.1.50", messagePort: 15101, clipboardPort: 15100, attempt: 2))

        #expect(
            policy.evaluateDisconnect(
                sessionID: ObjectIdentifier(dummyB),
                isOutbound: true,
                kind: .message,
                remainingMessageSessions: 0) == .exhausted(host: "192.168.1.50", maxAttempts: 2))
    }
}
