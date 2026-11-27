public import Foundation
private import OSLog

/// Handles batch AES-CBC stream framing, IV block discard, magic/checksum validation, and packet extraction.
public final class MWBStreamFramer {
    public struct ParseResult: Sendable {
        public struct RejectedPacket: Equatable, Sendable {
            public let actualMagic: UInt16
            public let expectedMagic: UInt16
            public let rawType: UInt8
            public let length: Int
        }

        public let packets: [MWBPacket]
        public let rejected: [RejectedPacket]
    }

    private var encryptor: MWBStreamCipher?
    private var decryptor: MWBStreamCipher?
    private let magicNumber: UInt32

    private var encryptedBuffer = Data()
    private var plainBuffer = Data()
    private var plainReadOffset = 0
    private var initialBlockDiscarded = false
    private var packetCounter: Int32 = 0

    public init(crypto: MWBCryptoMaterial) {
        self.magicNumber = crypto.magicNumber
        self.encryptor = crypto.makeEncryptor()
        self.decryptor = crypto.makeDecryptor()
    }

    public func makeInitialIVBlock() -> Data? {
        let random = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        return self.encryptor?.update(random)
    }

    public func encodeForSend(_ packet: MWBPacket) -> (packet: MWBPacket, encrypted: Data)? {
        var prepared = packet
        if prepared.id == 0 {
            self.packetCounter &+= 1
            prepared.id = self.packetCounter
        }
        prepared.finalizeForSend(magicNumber: self.magicNumber)
        let targetSize = prepared.isBigPackage ? MWBPacket.extendedSize : MWBPacket.baseSize
        prepared.data = prepared.data.prefix(targetSize)

        guard let encrypted = self.encryptor?.update(prepared.data) else { return nil }
        return (prepared, encrypted)
    }

    public func receiveEncrypted(_ data: Data) -> ParseResult {
        self.encryptedBuffer.append(data)
        self.decryptAvailableBlocks()
        return self.parseAvailablePackets()
    }

    public func close() {
        self.encryptor?.close()
        self.decryptor?.close()
        self.encryptor = nil
        self.decryptor = nil
        self.encryptedBuffer.removeAll()
        self.plainBuffer.removeAll()
        self.plainReadOffset = 0
    }

    private func decryptAvailableBlocks() {
        let availableBlocksBytes = (self.encryptedBuffer.count / 16) * 16
        if availableBlocksBytes > 0 {
            let chunk = Data(self.encryptedBuffer.prefix(availableBlocksBytes))
            self.encryptedBuffer.removeFirst(availableBlocksBytes)
            if let decrypted = self.decryptor?.update(chunk), decrypted.count == availableBlocksBytes {
                self.plainBuffer.append(decrypted)
            } else {
                MBLogger.network.error("MWB batch decrypt failed or size mismatch")
            }
        }

        if !self.initialBlockDiscarded, (self.plainBuffer.count - self.plainReadOffset) >= 16 {
            self.plainReadOffset += 16
            self.initialBlockDiscarded = true
        }
    }

    private func parseAvailablePackets() -> ParseResult {
        var packets: [MWBPacket] = []
        var rejected: [ParseResult.RejectedPacket] = []

        while (self.plainBuffer.count - self.plainReadOffset) >= MWBPacket.baseSize {
            let rawType = self.plainBuffer[self.plainBuffer.startIndex + self.plainReadOffset]
            let needed = MWBPacket.isBigType(rawType: rawType) ? MWBPacket.extendedSize : MWBPacket.baseSize
            if (self.plainBuffer.count - self.plainReadOffset) < needed { break }

            let start = self.plainBuffer.startIndex + self.plainReadOffset
            let packetData = Data(self.plainBuffer[start..<(start + needed)])
            self.plainReadOffset += needed

            var packet = MWBPacket(data: packetData)
            guard packet.validate(magicNumber: self.magicNumber) else {
                let expected = UInt16((self.magicNumber >> 16) & 0xFFFF)
                rejected.append(
                    ParseResult.RejectedPacket(
                        actualMagic: packet.magicHigh16,
                        expectedMagic: expected,
                        rawType: rawType,
                        length: packet.data.count))
                continue
            }

            packet.data[1] = 0
            packet.data[2] = 0
            packet.data[3] = 0
            packets.append(packet)
        }

        self.compactPlainBufferIfNeeded()
        return ParseResult(packets: packets, rejected: rejected)
    }

    private func compactPlainBufferIfNeeded() {
        if self.plainReadOffset >= self.plainBuffer.count {
            self.plainBuffer.removeAll(keepingCapacity: true)
            self.plainReadOffset = 0
        } else if self.plainReadOffset >= 4096 {
            self.plainBuffer.removeFirst(self.plainReadOffset)
            self.plainReadOffset = 0
        }
    }
}

/// Pure serialization helpers for MWB clipboard, file-drop, and machine matrix payloads.
public enum MWBClipboardCodec {
    public static func encodeClipboardText(_ text: String) -> Data? {
        guard let textData = text.data(using: .utf16LittleEndian) else { return nil }
        return MWBCompression.deflateCompress(textData)
    }

    public static func decodeClipboardText(_ data: Data) -> String? {
        guard let decompressed = MWBCompression.deflateDecompress(data) else { return nil }
        return String(data: decompressed, encoding: .utf16LittleEndian)
    }

    public static func encodeFileDrop(_ urls: [URL]) -> Data {
        let joined = urls.map(\.path).joined(separator: "\0") + "\0\0"
        return joined.data(using: .utf16LittleEndian) ?? Data()
    }

    public static func decodeFileDrop(_ data: Data) -> [URL]? {
        guard let string = String(data: data, encoding: .utf16LittleEndian) else { return nil }
        let urls =
            string
            .split(separator: "\0")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
        return urls.isEmpty ? nil : urls
    }

    public static func chunkPackets(
        type: MWBPacketType,
        data: Data,
        localId: Int32,
        chunkSize: Int = 48
    ) -> [MWBPacket] {
        guard chunkSize > 0 else { return [] }
        var packets: [MWBPacket] = []
        var index = 0
        while index < data.count {
            let end = min(index + chunkSize, data.count)
            var packet = MWBPacket()
            packet.type = type
            packet.src = localId
            packet.des = Int32(255)
            packet.clipboardPayload = data.subdata(in: index..<end)
            packets.append(packet)
            index = end
        }
        return packets
    }

    public static func encodeMatrixPackets(
        machines: [String],
        twoRow: Bool,
        swap: Bool
    ) -> [MWBPacket] {
        let paddedMachines = machines + Array(repeating: "", count: max(0, 4 - machines.count))
        let flags: UInt8 = (swap ? 0x02 : 0x00) | (twoRow ? 0x04 : 0x00)

        return paddedMachines.prefix(4).enumerated().map { index, name in
            var packet = MWBPacket()
            packet.rawType = MWBPacketType.matrix.rawValue | flags
            packet.src = Int32(index + 1)
            packet.des = Int32(255)
            packet.machineName = name
            return packet
        }
    }

    public static func decodeMatrixPacket(_ packet: MWBPacket) -> (names: [String], twoRow: Bool, swap: Bool) {
        let names = packet.machineName
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let flags = packet.rawType & 0x0F
        let swap = (flags & 0x02) != 0
        let twoRow = (flags & 0x04) != 0
        return (names, twoRow, swap)
    }
}
