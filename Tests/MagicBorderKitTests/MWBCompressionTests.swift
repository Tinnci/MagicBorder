import Foundation
import Testing

@testable import MagicBorderKit

@Suite("MWBCompression")
struct MWBCompressionTests {
    @Test func emptyDataRoundTripsWithoutError() {
        #expect(MWBCompression.deflateCompress(Data()) == Data())
        #expect(MWBCompression.deflateDecompress(Data()) == Data())
    }

    @Test func smallUTF16TextRoundTripsCleanly() throws {
        let text = "Hello MagicBorder Windows Clipboard 🚀"
        let raw = try #require(text.data(using: .utf16LittleEndian))
        let compressed = try #require(MWBCompression.deflateCompress(raw))
        let decompressed = try #require(MWBCompression.deflateDecompress(compressed))

        #expect(decompressed == raw)
        #expect(String(data: decompressed, encoding: .utf16LittleEndian) == text)
    }

    @Test func streamingDecompressionHandlesHighCompressionRatioOver64KB() throws {
        // Highly repetitive UTF-16LE exceeds 4x compressed size and > 64KB buffer.
        let largeText = String(repeating: "MagicBorder-Clipboard-Sync-", count: 6000)
        let raw = try #require(largeText.data(using: .utf16LittleEndian))
        #expect(raw.count > 200_000)

        let compressed = try #require(MWBCompression.deflateCompress(raw))
        #expect(raw.count > compressed.count * 10)

        let decompressed = try #require(MWBCompression.deflateDecompress(compressed))
        #expect(decompressed == raw)
    }

    @Test func invalidZlibStreamReturnsNil() {
        let garbage = Data([0xFF, 0x00, 0xAA, 0xBB, 0xCC, 0xDD])
        #expect(MWBCompression.deflateDecompress(garbage) == nil)
    }
}
