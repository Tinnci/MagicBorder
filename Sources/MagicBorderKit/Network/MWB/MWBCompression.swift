import Compression
public import Foundation

/// Streaming zlib compression/decompression without fixed-size output truncation.
public enum MWBCompression {
    private static let chunkSize = 64 * 1024
    private static let maxDecompressedSize = 64 * 1024 * 1024

    public static func deflateCompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        return self.process(data, operation: COMPRESSION_STREAM_ENCODE, maxOutputSize: nil)
    }

    public static func deflateDecompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        return self.process(
            data,
            operation: COMPRESSION_STREAM_DECODE,
            maxOutputSize: self.maxDecompressedSize)
    }

    private static func process(
        _ data: Data,
        operation: compression_stream_operation,
        maxOutputSize: Int?
    ) -> Data? {
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: self.chunkSize)
        defer { dstBuffer.deallocate() }

        return data.withUnsafeBytes { (srcBuffer: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }

            var stream = compression_stream(
                dst_ptr: dstBuffer,
                dst_size: self.chunkSize,
                src_ptr: srcBase,
                src_size: 0,
                state: nil)
            guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                return nil
            }
            defer { compression_stream_destroy(&stream) }

            stream.src_ptr = srcBase
            stream.src_size = data.count

            var output = Data()
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)

            while true {
                stream.dst_ptr = dstBuffer
                stream.dst_size = self.chunkSize
                let status = compression_stream_process(&stream, flags)

                let produced = self.chunkSize - stream.dst_size
                if produced > 0 {
                    if let maxOutputSize, output.count + produced > maxOutputSize {
                        return nil
                    }
                    output.append(dstBuffer, count: produced)
                }

                switch status {
                case COMPRESSION_STATUS_OK:
                    continue
                case COMPRESSION_STATUS_END:
                    return output
                default:
                    return nil
                }
            }
        }
    }
}
