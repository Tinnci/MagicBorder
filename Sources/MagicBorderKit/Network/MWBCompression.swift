import Compression
import Foundation

enum MWBCompression {
    static func deflateCompress(_ data: Data) -> Data? {
        data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcPtr.baseAddress else { return nil }
            let srcSize = data.count

            let dstBufferSize = max(64 * 1024, srcSize + (srcSize / 2))
            var dstData = Data(count: dstBufferSize)

            let encodedSize = dstData.withUnsafeMutableBytes { dstPtr in
                compression_encode_buffer(
                    dstPtr.bindMemory(to: UInt8.self).baseAddress!,
                    dstBufferSize,
                    srcBase.assumingMemoryBound(to: UInt8.self),
                    srcSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }

            guard encodedSize > 0 else { return nil }
            return dstData.prefix(encodedSize)
        }
    }

    static func deflateDecompress(_ data: Data) -> Data? {
        data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcPtr.baseAddress else { return nil }
            let srcSize = data.count

            let dstBufferSize = max(64 * 1024, srcSize * 4)
            var dstData = Data(count: dstBufferSize)

            let decodedSize = dstData.withUnsafeMutableBytes { dstPtr in
                compression_decode_buffer(
                    dstPtr.bindMemory(to: UInt8.self).baseAddress!,
                    dstBufferSize,
                    srcBase.assumingMemoryBound(to: UInt8.self),
                    srcSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }

            guard decodedSize > 0 else { return nil }
            return dstData.prefix(decodedSize)
        }
    }
}