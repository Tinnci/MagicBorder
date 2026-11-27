import Foundation
import Testing

@testable import MagicBorderKit

@Suite("CompatibilitySettings")
@MainActor
struct CompatibilitySettingsTests {
    @Test func defaultsUseMWBPortsWhenNoValuesArePersisted() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let settings = MBCompatibilitySettings(defaults: defaults)

        #expect(settings.messagePort == 15101)
        #expect(settings.clipboardPort == 15100)
    }

    @Test func invalidPersistedPortsFallBackToDefaults() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        defaults.set(70000, forKey: "compat.messagePort")
        defaults.set(-1, forKey: "compat.clipboardPort")

        let settings = MBCompatibilitySettings(defaults: defaults)

        #expect(settings.messagePort == 15101)
        #expect(settings.clipboardPort == 15100)
    }

    @Test func zeroPortsFallBackToDefaults() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        defaults.set(0, forKey: "compat.messagePort")
        defaults.set(0, forKey: "compat.clipboardPort")

        let settings = MBCompatibilitySettings(defaults: defaults)

        #expect(settings.messagePort == 15101)
        #expect(settings.clipboardPort == 15100)
    }

    @Test func persistedSettingsAreReadBackFromInjectedDefaults() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.shareClipboard = false
        settings.transferFiles = true
        settings.messagePort = 15111
        settings.clipboardPort = 15110
        settings.securityKey = "1234567890ABCDEF"

        let restored = MBCompatibilitySettings(defaults: defaults)

        #expect(!restored.shareClipboard)
        #expect(restored.transferFiles)
        #expect(restored.messagePort == 15111)
        #expect(restored.clipboardPort == 15110)
        #expect(restored.securityKey == "1234567890ABCDEF")
    }

    @Test func securityKeyValidationReportsTypedStatus() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)

        settings.securityKey = "short"
        #expect(!settings.validateSecurityKey())
        #expect(settings.validationStatus == .tooShort)

        settings.securityKey = "1234567890ABCDEF"
        #expect(settings.validateSecurityKey())
        #expect(settings.validationStatus == .valid)
    }
}
