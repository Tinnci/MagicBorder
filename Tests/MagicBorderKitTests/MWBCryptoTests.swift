import CommonCrypto
import CryptoKit
import Foundation
import Testing

@testable import MagicBorderKit

@Suite("MWBCrypto")
struct MWBCryptoTests {
    @Test func keyDerivationRejectsShortKeysAndCachesValidKeys() throws {
        MWBKeyDerivation.clearCache()

        #expect(MWBKeyDerivation.derive(from: "too-short") == nil)
        #expect(MWBKeyDerivation.derive(from: "1234 5678 9012 345") == nil)

        let first = try #require(MWBKeyDerivation.derive(from: "Magic Border Key 2026"))
        let second = try #require(MWBKeyDerivation.derive(from: "MagicBorderKey2026"))

        #expect(first == second)
        #expect(first.sessionKey.count == 32)
        #expect(first.iv.count == 16)
    }

    @Test func magicNumberMatchesReference50001RoundSHA512() {
        let key = "TestSecurityKey16"
        let actual = MWBKeyDerivation.calculateMagicNumber(from: key)

        var padded = Data(count: 32)
        let keyBytes = Data(key.utf8)
        padded.replaceSubrange(0..<min(keyBytes.count, 32), with: keyBytes)

        var hash = Data(SHA512.hash(data: padded))
        for _ in 0..<50_000 {
            hash = Data(SHA512.hash(data: hash))
        }
        let expected =
            (UInt32(hash[0]) << 23)
            + (UInt32(hash[1]) << 16)
            + (UInt32(hash[hash.count - 1]) << 8)
            + UInt32(hash[2])

        #expect(actual == expected)
    }

    @Test func streamCipherRoundTripsAcrossMultipleChunksAndClosesCleanly() throws {
        let material = try #require(MWBKeyDerivation.derive(from: "1234567890ABCDEF"))
        let encryptor = try #require(material.makeEncryptor())
        let decryptor = try #require(material.makeDecryptor())

        let plaintextA = Data((0..<32).map { UInt8($0) })
        let plaintextB = Data((32..<96).map { UInt8($0) })

        let cipherA = try #require(encryptor.update(plaintextA))
        let cipherB = try #require(encryptor.update(plaintextB))

        let decryptedA = try #require(decryptor.update(cipherA))
        let decryptedB = try #require(decryptor.update(cipherB))

        #expect(decryptedA == plaintextA)
        #expect(decryptedB == plaintextB)

        // Unaligned decrypt input must be rejected cleanly.
        #expect(decryptor.update(Data([1, 2, 3])) == nil)

        encryptor.close()
        decryptor.close()
        #expect(encryptor.update(plaintextA) == nil)
        #expect(decryptor.update(cipherA) == nil)
    }
}
