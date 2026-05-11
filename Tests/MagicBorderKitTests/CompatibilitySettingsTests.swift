@testable import MagicBorderKit
import XCTest

@MainActor
final class CompatibilitySettingsTests: XCTestCase {
    func testDefaultsUseMWBPortsWhenNoValuesArePersisted() {
        let (defaults, suiteName) = self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = MBCompatibilitySettings(defaults: defaults)

        XCTAssertEqual(settings.messagePort, 15101)
        XCTAssertEqual(settings.clipboardPort, 15100)
    }

    func testInvalidPersistedPortsFallBackToDefaults() {
        let (defaults, suiteName) = self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(70000, forKey: "compat.messagePort")
        defaults.set(-1, forKey: "compat.clipboardPort")

        let settings = MBCompatibilitySettings(defaults: defaults)

        XCTAssertEqual(settings.messagePort, 15101)
        XCTAssertEqual(settings.clipboardPort, 15100)
    }

    func testZeroPortsFallBackToDefaults() {
        let (defaults, suiteName) = self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0, forKey: "compat.messagePort")
        defaults.set(0, forKey: "compat.clipboardPort")

        let settings = MBCompatibilitySettings(defaults: defaults)

        XCTAssertEqual(settings.messagePort, 15101)
        XCTAssertEqual(settings.clipboardPort, 15100)
    }

    func testPersistedSettingsAreReadBackFromInjectedDefaults() {
        let (defaults, suiteName) = self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.shareClipboard = false
        settings.transferFiles = true
        settings.messagePort = 15111
        settings.clipboardPort = 15110
        settings.securityKey = "1234567890ABCDEF"

        let restored = MBCompatibilitySettings(defaults: defaults)

        XCTAssertFalse(restored.shareClipboard)
        XCTAssertTrue(restored.transferFiles)
        XCTAssertEqual(restored.messagePort, 15111)
        XCTAssertEqual(restored.clipboardPort, 15110)
        XCTAssertEqual(restored.securityKey, "1234567890ABCDEF")
    }

    func testSecurityKeyValidationReportsSuccessAndFailure() {
        let (defaults, suiteName) = self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = MBCompatibilitySettings(defaults: defaults)

        settings.securityKey = "short"
        XCTAssertFalse(settings.validateSecurityKey())
        XCTAssertNotNil(settings.validationMessage)

        settings.securityKey = "1234567890ABCDEF"
        XCTAssertTrue(settings.validateSecurityKey())
        XCTAssertEqual(settings.validationMessage, "Success")
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "MagicBorderTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
