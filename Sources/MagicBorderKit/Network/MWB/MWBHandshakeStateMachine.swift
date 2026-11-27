import Foundation

/// Pure state machine managing MWB challenge-response handshake packets.
public struct MWBHandshakeStateMachine: Sendable {
    public enum AckOutcome: Equatable, Sendable {
        case verified(MWBPeer)
        case failedFirstTime
        case ignored
    }

    public private(set) var challenge: (Int32, Int32, Int32, Int32)?
    public private(set) var isVerified = false
    public private(set) var ackFailures = 0
    public var pendingPeerName: String?

    public init() {}

    public mutating func makeOutboundHandshakeBurst(
        localId: Int32,
        localName: String,
        count: Int = 10
    ) -> [MWBPacket] {
        var randomData = Data(count: MWBPacket.extendedSize)
        randomData.withUnsafeMutableBytes { buffer in
            for index in 0..<buffer.count {
                buffer[index] = UInt8.random(in: 0...255)
            }
        }

        var packet = MWBPacket(data: randomData)
        packet.type = .handshake
        packet.src = localId
        packet.des = 0
        packet.machineName = localName

        self.challenge = (packet.machine1, packet.machine2, packet.machine3, packet.machine4)
        self.ackFailures = 0
        return Array(repeating: packet, count: max(0, count))
    }

    public func makeHandshakeAck(for incoming: MWBPacket, localName: String) -> MWBPacket {
        var ack = incoming
        ack.type = .handshakeAck
        ack.src = 0
        ack.machineName = localName
        ack.machine1 = ~incoming.machine1
        ack.machine2 = ~incoming.machine2
        ack.machine3 = ~incoming.machine3
        ack.machine4 = ~incoming.machine4
        return ack
    }

    public mutating func processAck(_ packet: MWBPacket) -> AckOutcome {
        guard !self.isVerified, let challenge = self.challenge else {
            return .ignored
        }

        if packet.machine1 == ~challenge.0,
            packet.machine2 == ~challenge.1,
            packet.machine3 == ~challenge.2,
            packet.machine4 == ~challenge.3
        {
            self.isVerified = true
            self.challenge = nil
            self.ackFailures = 0
            return .verified(MWBPeer(id: packet.src, name: packet.machineName))
        }

        self.ackFailures += 1
        return self.ackFailures == 1 ? .failedFirstTime : .ignored
    }
}
