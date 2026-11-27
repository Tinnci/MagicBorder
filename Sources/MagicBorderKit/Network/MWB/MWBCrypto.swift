public import CommonCrypto
public import Foundation
private import OSLog
private import os

/// Immutable derived MWB session key material.
public struct MWBCryptoMaterial: Equatable, Sendable {
    public let sessionKey: Data
    public let magicNumber: UInt32
    public let iv: Data

    public init(sessionKey: Data, magicNumber: UInt32, iv: Data = MWBKeyDerivation.legacyIV) {
        self.sessionKey = sessionKey
        self.magicNumber = magicNumber
        self.iv = iv
    }

    public func makeEncryptor() -> MWBStreamCipher? {
        MWBStreamCipher(operation: CCOperation(kCCEncrypt), key: self.sessionKey, iv: self.iv)
    }

    public func makeDecryptor() -> MWBStreamCipher? {
        MWBStreamCipher(operation: CCOperation(kCCDecrypt), key: self.sessionKey, iv: self.iv)
    }
}

/// Pure, thread-safe key derivation & caching for Mouse Without Borders compatibility mode.
public enum MWBKeyDerivation {
    private static let saltString = "18446744073709551615"
    private static let iterations: UInt32 = 50_000
    private static let keyLength = 32
    public static let legacyIV = Data("1844674407370955".utf8)

    private static let cache = OSAllocatedUnfairLock<[String: MWBCryptoMaterial]>(initialState: [:])

    public static func derive(from secretKey: String) -> MWBCryptoMaterial? {
        let trimmedKey = secretKey.replacingOccurrences(of: " ", with: "")
        guard trimmedKey.count >= 16,
            let passwordData = trimmedKey.data(using: .utf8),
            let saltData = self.saltString.data(using: .utf16LittleEndian)
        else { return nil }

        if let cached = self.cache.withLock({ $0[trimmedKey] }) {
            return cached
        }

        var derivedKeyData = Data(count: self.keyLength)
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
                        self.iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        self.keyLength)
                }
            }
        }

        guard result == kCCSuccess else {
            MBLogger.security.error("Failed to derive MWB key: \(result)")
            return nil
        }

        let magicNumber = self.calculateMagicNumber(from: trimmedKey)
        let material = MWBCryptoMaterial(
            sessionKey: derivedKeyData,
            magicNumber: magicNumber,
            iv: self.legacyIV)

        self.cache.withLock { $0[trimmedKey] = material }
        MBLogger.security.info("MWB keys derived successfully. Magic: \(magicNumber)")
        return material
    }

    public static func clearCache() {
        self.cache.withLock { $0.removeAll() }
    }

    /// Computes MWB's 24-bit magic number using 50,001 SHA-512 rounds without per-round heap allocations.
    public static func calculateMagicNumber(from key: String) -> UInt32 {
        let trimmedKey = key.replacingOccurrences(of: " ", with: "")
        guard let keyData = trimmedKey.data(using: .utf8) else { return 0 }

        var initial = [UInt8](repeating: 0, count: 32)
        let copyCount = min(keyData.count, 32)
        for index in 0..<copyCount {
            initial[index] = keyData[index]
        }

        var hashBuffer = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        var nextBuffer = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        initial.withUnsafeBytes { src in
            hashBuffer.withUnsafeMutableBytes { dst in
                _ = CC_SHA512(
                    src.baseAddress,
                    CC_LONG(initial.count),
                    dst.baseAddress?.assumingMemoryBound(to: UInt8.self))
            }
        }

        for _ in 0..<50_000 {
            hashBuffer.withUnsafeBytes { src in
                nextBuffer.withUnsafeMutableBytes { dst in
                    _ = CC_SHA512(
                        src.baseAddress,
                        CC_LONG(hashBuffer.count),
                        dst.baseAddress?.assumingMemoryBound(to: UInt8.self))
                }
            }
            swap(&hashBuffer, &nextBuffer)
        }

        let lastByte = hashBuffer[hashBuffer.count - 1]
        return (UInt32(hashBuffer[0]) << 23)
            + (UInt32(hashBuffer[1]) << 16)
            + (UInt32(lastByte) << 8)
            + UInt32(hashBuffer[2])
    }
}

/// Reference-counted streaming AES-256-CBC cipher (zero padding) that always releases `CCCryptorRef` on `deinit`.
public final class MWBStreamCipher {
    private var cryptor: CCCryptorRef?
    private let isEncrypting: Bool

    public init?(operation: CCOperation, key: Data, iv: Data) {
        var cryptorOut: CCCryptorRef?
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreate(
                    operation,
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(0),
                    keyBytes.baseAddress,
                    key.count,
                    ivBytes.baseAddress,
                    &cryptorOut)
            }
        }

        guard status == kCCSuccess, let cryptorOut else {
            return nil
        }

        self.cryptor = cryptorOut
        self.isEncrypting = operation == CCOperation(kCCEncrypt)
    }

    deinit {
        self.close()
    }

    public func update(_ data: Data) -> Data? {
        guard let cryptor = self.cryptor else { return nil }

        let blockSize = kCCBlockSizeAES128
        var input = data
        let remainder = input.count % blockSize
        if self.isEncrypting {
            if remainder != 0 {
                input.append(Data(count: blockSize - remainder))
            }
        } else {
            guard remainder == 0 else { return nil }
        }

        guard !input.isEmpty else { return Data() }

        let outLength = CCCryptorGetOutputLength(cryptor, input.count, false)
        var outData = Data(count: outLength)
        var bytesOut: size_t = 0

        let status = outData.withUnsafeMutableBytes { outBytes in
            input.withUnsafeBytes { inBytes in
                CCCryptorUpdate(
                    cryptor,
                    inBytes.baseAddress,
                    input.count,
                    outBytes.baseAddress,
                    outLength,
                    &bytesOut)
            }
        }

        guard status == kCCSuccess else { return nil }
        return outData.prefix(bytesOut)
    }

    public func close() {
        if let cryptor = self.cryptor {
            CCCryptorRelease(cryptor)
            self.cryptor = nil
        }
    }
}
