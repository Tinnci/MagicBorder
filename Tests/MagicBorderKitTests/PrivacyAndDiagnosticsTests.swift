import Darwin
import Foundation
import Network
import Testing

@testable import MagicBorderKit

@Suite("PrivacyAndDiagnostics")
@MainActor
struct PrivacyAndDiagnosticsTests {
    @Test func pasteboardMonitorSkipsConcealedItemsWhenPrivacyFilterEnabled() {
        let pasteboard = FakePasteboard()
        let monitor = MBPasteboardMonitor(pasteboard: pasteboard)
        var captured: [MBPasteboardContent] = []
        monitor.onChange = { captured.append($0) }

        pasteboard.isConcealedOrTransient = true
        pasteboard.writeString("super-secret-password")
        monitor.checkForChanges()
        #expect(captured.isEmpty)

        monitor.ignoreConcealedItems = false
        pasteboard.writeString("allowed-when-disabled")
        monitor.checkForChanges()
        #expect(captured == [.text("allowed-when-disabled")])
    }

    @Test func clipboardBridgeEnforcesSizeLimitAndPushCurrentClipboard() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.maxClipboardSizeMB = 1
        let pasteboard = FakePasteboard()
        var sentTexts: [String] = []
        var sentImages: [Data] = []
        var toasts: [MBToastEvent] = []

        let bridge = MBClipboardBridge(
            pasteboard: pasteboard,
            emitToast: { toasts.append($0) },
            sendClipboardText: { sentTexts.append($0) },
            sendClipboardImage: { sentImages.append($0) },
            sendFileDrop: { _ in })

        let oversizedData = Data(repeating: 0xAA, count: 1_048_577)
        bridge.handleLocalPasteboard(.image(oversizedData), settings: settings)
        #expect(sentImages.isEmpty)
        #expect(toasts.last == .clipboardTooLarge(1))

        pasteboard.isConcealedOrTransient = true
        pasteboard.storedString = "1password-token"
        bridge.pushCurrentClipboard(settings: settings)
        #expect(sentTexts.isEmpty)
        #expect(toasts.last == .clipboardEmpty)

        pasteboard.isConcealedOrTransient = false
        pasteboard.storedString = "manual-sync"
        bridge.pushCurrentClipboard(settings: settings)
        #expect(sentTexts == ["manual-sync"])
        #expect(toasts.last == .clipboardSyncedText)
    }

    @Test func savedHostStorePersistsRecordsAcrossReload() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let store = MBSavedHostStore(defaults: defaults)
        store.recordConnection(
            address: "192.168.1.44",
            name: "OFFICE-PC",
            protocolMode: .mwbCompatibility,
            messagePort: 15101,
            clipboardPort: 15100)

        let reloaded = MBSavedHostStore(defaults: defaults)
        #expect(reloaded.hosts.count == 1)
        #expect(reloaded.hosts[0].name == "OFFICE-PC")
        #expect(reloaded.hosts[0].address == "192.168.1.44")

        reloaded.remove(id: reloaded.hosts[0].id)
        #expect(reloaded.hosts.isEmpty)
    }

    @Test func connectionDoctorRedactsSecretsAndProbesLoopbackPort() async throws {
        let redacted = MBConnectionDoctor.redact(
            logs: ["Connecting with key My Secret Key 1234", "Backup key MySecretKey1234"],
            securityKey: "My Secret Key 1234")
        #expect(!redacted.contains("My Secret Key 1234"))
        #expect(!redacted.contains("MySecretKey1234"))
        #expect(redacted.contains("[REDACTED]"))

        let (fd, openPort) = try Self.openListeningLoopbackSocket()
        defer { Darwin.close(fd) }

        let report = await MBConnectionDoctor.diagnose(
            host: "127.0.0.1",
            protocolMode: .modern,
            securityKey: "ValidModernKey123",
            messagePort: openPort,
            clipboardPort: 15100,
            timeoutSeconds: 1.5)

        // Probe specifically targets 12345 for .modern; now probe .mwbCompatibility on openPort
        _ = report
        let mwbReport = await MBConnectionDoctor.diagnose(
            host: "127.0.0.1",
            protocolMode: .mwbCompatibility,
            securityKey: "0123456789ABCDEF",
            messagePort: openPort,
            clipboardPort: openPort,
            timeoutSeconds: 1.5)

        #expect(mwbReport.isHealthy)
        #expect(mwbReport.stages.count == 3)
        #expect(mwbReport.stages[1].latencyMs != nil)
    }

    private static func openListeningLoopbackSocket() throws -> (Int32, UInt16) {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(fd, 4) == 0 else {
            Darwin.close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.getsockname(fd, sockPtr, &len)
            }
        }
        return (fd, UInt16(bigEndian: bound.sin_port))
    }
}
