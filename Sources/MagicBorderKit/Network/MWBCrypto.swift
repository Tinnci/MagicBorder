import CommonCrypto
import CryptoKit
import Foundation

// Polyfill for PBKDF2 if needed (Apple CryptoKit in Swift 6 might have it, but usually CommonCrypto is safer fallback for strict legacy compliance)
// However, CryptoKit's RFC2898DeriveBytes equivalent is `KDF.PBKDF2` if available or we use CommonCrypto.
// Let's use CommonCrypto for maximum control over rounds and Algo.

public class MWBCrypto: @unchecked Sendable {
    public static let shared = MWBCrypto()

    // Constants from SocketStuff.cs
    private let saltString = "18446744073709551615"
    private let iterations: UInt32 = 50000
    private let keyLength = 32  // 256 bits

    public var sessionKey: Data?
    public var magicNumber: UInt32 = 0

    public func deriveKey(from secretKey: String) {
        guard let passwordData = secretKey.data(using: .utf8),
            let saltData = saltString.data(using: .utf8)
        else {
            return
        }

        // ... (lines 27-47 omitted)
        // PBKDF2 (HMAC-SHA512)
        // Using CommonCrypto legacy call
        var derivedKeyData = Data(count: keyLength)
        let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                saltData.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                        iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        if result == kCCSuccess {
            self.sessionKey = derivedKeyData
            self.magicNumber = calculateMagicNumber(from: secretKey)
            print("Keys derived successfully. Magic: \(magicNumber)")
        } else {
            print("Failed to derive key: \(result)")
        }
    }

    // Magic Number Calculation (Reverse engineered from Encryption.cs)
    public func calculateMagicNumber(from key: String) -> UInt32 {
        guard let keyData = key.data(using: .utf8) else { return 0 }

        // Pad or truncate to 32 bytes (PACKAGE_SIZE) - Encryption.cs logic
        var bytes = Data(count: 32)
        let copyCount = min(keyData.count, 32)
        bytes.replaceSubrange(0..<copyCount, with: keyData)

        // Double SHA512 loop
        let hash = SHA512.hash(data: bytes)
        var currentHashData = Data(hash)

        for _ in 0..<50000 {
            let nextHash = SHA512.hash(data: currentHashData)
            currentHashData = Data(nextHash)
        }

        // Extract 24-bit hash: (hash[0] << 23) + (hash[1] << 16) + (hash[^1] << 8) + hash[2]
        // Note: hash[^1] is the LAST byte of the 64-byte SHA512 hash.
        let h = currentHashData
        let lastByte = h[h.count - 1]

        let val: UInt32 =
            (UInt32(h[0]) << 23) + (UInt32(h[1]) << 16) + (UInt32(lastByte) << 8) + UInt32(h[2])

        return val
    }

    // IV Generation (Legacy "Flaw")
    func generateIV() -> Data {
        // "18446744073709551615" truncated to 16 bytes
        let ivString = "18446744073709551615"
        var ivData = ivString.data(using: .utf8)!
        if ivData.count > 16 {
            ivData = ivData.prefix(16)
        } else if ivData.count < 16 {
            // Pad with spaces
            // ... implementation if needed, but this string is len 20, so prefix(16) works.
            // "1844674407370955"
        }
        return ivData
    }

    // AES-256-CBC Encrypt
    // Using CommonCrypto for raw AES-CBC if CryptoKit.AES.GCM is not compatible (MWB uses CBC)
    public func encrypt(_ data: Data) -> Data? {
        guard let key = sessionKey else { return nil }
        let iv = generateIV()

        // Output buffer (size + one block for padding)
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesEncrypted: Int = 0

        let cryptStatus = buffer.withUnsafeMutableBytes { bufferBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),  // Encryption.cs uses PaddingMode.Zeros? Checked: PaddingMode.Zeros.
                            // WARNING: MWB uses PaddingMode.Zeros. kCCOptionPKCS7Padding is default.
                            // If MWB uses Zeros and Stream mode, we might need manual padding or NoPadding if data is aligned.
                            // Package size is 32 (aligned to 16), so NoPadding might work if we ensure input is multiple of 16.
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            bufferBytes.baseAddress, bufferSize,
                            &numBytesEncrypted
                        )
                    }
                }
            }
        }

        if cryptStatus == kCCSuccess {
            return buffer.prefix(numBytesEncrypted)
        }
        return nil
    }

    public func decrypt(_ data: Data) -> Data? {
        guard let key = sessionKey else { return nil }
        let iv = generateIV()

        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesDecrypted: Int = 0

        let cryptStatus = buffer.withUnsafeMutableBytes { bufferBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(0),  // No padding for decrypt if matched?
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            bufferBytes.baseAddress, bufferSize,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }

        if cryptStatus == kCCSuccess {
            return buffer.prefix(numBytesDecrypted)
        }
        return nil
    }
}

// MARK: - Streaming Cipher (CBC, Zero Padding)

public struct MWBStreamCipher {
    private var cryptor: CCCryptorRef?

    public init?(operation: CCOperation, key: Data, iv: Data) {
        var cryptorOut: CCCryptorRef?
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreate(
                    operation,
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(0),
                    keyBytes.baseAddress, key.count,
                    ivBytes.baseAddress,
                    &cryptorOut
                )
            }
        }

        guard status == kCCSuccess, let cryptorOut else {
            return nil
        }

        self.cryptor = cryptorOut
    }

    public mutating func update(_ data: Data) -> Data? {
        guard let cryptor else { return nil }

        let blockSize = kCCBlockSizeAES128
        var padded = data
        let remainder = padded.count % blockSize
        if remainder != 0 {
            padded.append(Data(count: blockSize - remainder))
        }

        let outLength = CCCryptorGetOutputLength(cryptor, padded.count, false)
        var outData = Data(count: outLength)
        var bytesOut: size_t = 0

        let status = outData.withUnsafeMutableBytes { outBytes in
            padded.withUnsafeBytes { inBytes in
                CCCryptorUpdate(
                    cryptor,
                    inBytes.baseAddress, padded.count,
                    outBytes.baseAddress, outLength,
                    &bytesOut
                )
            }
        }

        guard status == kCCSuccess else { return nil }
        return outData.prefix(bytesOut)
    }

    public mutating func final() -> Data? {
        guard let cryptor else { return nil }

        let outLength = CCCryptorGetOutputLength(cryptor, 0, true)
        var outData = Data(count: outLength)
        var bytesOut: size_t = 0

        let status = outData.withUnsafeMutableBytes { outBytes in
            CCCryptorFinal(
                cryptor,
                outBytes.baseAddress, outLength,
                &bytesOut
            )
        }

        guard status == kCCSuccess else { return nil }
        return outData.prefix(bytesOut)
    }

    public mutating func close() {
        if let cryptor {
            CCCryptorRelease(cryptor)
            self.cryptor = nil
        }
    }
}

public extension MWBCrypto {
    func makeEncryptor() -> MWBStreamCipher? {
        guard let key = sessionKey else { return nil }
        let iv = generateIV()
        return MWBStreamCipher(operation: CCOperation(kCCEncrypt), key: key, iv: iv)
    }

    func makeDecryptor() -> MWBStreamCipher? {
        guard let key = sessionKey else { return nil }
        let iv = generateIV()
        return MWBStreamCipher(operation: CCOperation(kCCDecrypt), key: key, iv: iv)
    }
}
