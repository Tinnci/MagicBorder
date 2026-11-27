import Foundation
import Testing

@testable import MagicBorderKit

@Suite("NetworkManager")
@MainActor
struct NetworkManagerTests {
    @Test func transportMachineEventsUpdateConnectionStateAndRecoverActiveMachineOnDisconnect() async {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let compatibility = FakeTransport()
        let manager = self.makeManager(defaults: defaults, compatibilityTransport: compatibility)
        let remote = Machine(id: UUID(), name: "Windows", state: .connected, mwbPeerID: 42)

        compatibility.emit(.machineConnected(remote))
        await self.waitUntil { manager.connectedMachines.map(\.id) == [remote.id] }
        #expect(manager.connectedMachines.map(\.id) == [remote.id])

        compatibility.emit(.activeMachineChanged(remote.id, remote.name))
        await self.waitUntil { manager.activeMachineId == remote.id }
        #expect(manager.activeMachineId == remote.id)

        compatibility.emit(.machineDisconnected(remote.id))
        await self.waitUntil { manager.activeMachineId == nil && manager.connectedMachines.isEmpty }
        #expect(manager.activeMachineId == nil)
        #expect(manager.connectedMachines.isEmpty)
        #expect(manager.toast == .disconnected("Windows"))
    }

    @Test func applyCompatibilitySettingsUpdatesTransportAndDeduplicatesRepeats() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let compatibility = FakeTransport()
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.securityKey = "1234567890ABCDEF"
        settings.messagePort = 15111
        settings.clipboardPort = 15110
        let manager = self.makeManager(
            defaults: defaults,
            settings: settings,
            compatibilityTransport: compatibility)

        let initialCount = compatibility.calls.count
        manager.applyCompatibilitySettings()
        manager.applyCompatibilitySettings()

        #expect(compatibility.calls.count == initialCount)
        #expect(
            compatibility.calls.contains(
                .updateConfiguration(
                    securityKey: "1234567890ABCDEF",
                    messagePort: 15111,
                    clipboardPort: 15110)))
    }

    @Test func sendFileDropIsGatedByTransferFilesSetting() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let compatibility = FakeTransport()
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.transferFiles = false
        let manager = self.makeManager(
            defaults: defaults,
            settings: settings,
            compatibilityTransport: compatibility)

        let sent = manager.sendFileDrop([URL(fileURLWithPath: "/tmp/file.txt")])

        #expect(!sent)
        #expect(manager.toast == .fileTransferDisabled)
        #expect(
            !compatibility.calls.contains { call in
                if case .fileDrop = call { return true }
                return false
            })
    }

    @Test func sendFileDropUsesCurrentTransportWhenEnabled() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let compatibility = FakeTransport()
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.transferFiles = true
        let manager = self.makeManager(
            defaults: defaults,
            settings: settings,
            compatibilityTransport: compatibility)
        let url = URL(fileURLWithPath: "/tmp/file.txt")

        let sent = manager.sendFileDrop([url])

        #expect(sent)
        #expect(compatibility.calls.contains(.fileDrop([url])))
    }

    @Test func arrangementSyncSendsVisibleMachineNamesInArrangementOrder() async {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let compatibility = FakeTransport()
        let manager = self.makeManager(
            localName: "Mac",
            defaults: defaults,
            compatibilityTransport: compatibility)
        let first = Machine(id: UUID(), name: "Windows", state: .connected)
        let second = Machine(id: UUID(), name: "Linux", state: .connected)
        compatibility.emit(.machineConnected(first))
        compatibility.emit(.machineConnected(second))
        await self.waitUntil { manager.connectedMachines.count == 2 }

        manager.syncArrangement(
            machineIDs: [second.id, MBNetworkManager.localMachineUUID, first.id],
            twoRow: true,
            swap: false)

        #expect(compatibility.calls.contains(.matrix(["LINUX", "MAC", "WINDOWS"], true, false)))
    }

    @Test func transportLogAndErrorUpdatePairingDiagnostics() async {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let compatibility = FakeTransport()
        let manager = self.makeManager(defaults: defaults, compatibilityTransport: compatibility)

        compatibility.emit(.log("hello"))
        await self.waitUntil { manager.pairingDebugLog.contains { $0.contains("hello") } }
        compatibility.emit(.error("bad key"))
        await self.waitUntil { manager.pairingError == "bad key" }

        #expect(manager.pairingError == "bad key")
        #expect(manager.pairingDebugLog.contains { $0.contains("ERROR: bad key") })
    }

    @Test func arrangementOptionsEventUpdatesCompatibilitySettings() async {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let compatibility = FakeTransport()
        let manager = self.makeManager(defaults: defaults, compatibilityTransport: compatibility)

        compatibility.emit(.arrangementOptionsUpdated(twoRow: true, swap: true))
        await self.waitUntil {
            !manager.compatibilitySettings.matrixOneRow && manager.compatibilitySettings.matrixCircle
        }

        #expect(!manager.compatibilitySettings.matrixOneRow)
        #expect(manager.compatibilitySettings.matrixCircle)
    }

    @Test func sendMachineMatrixUppercasesNamesBeforeSending() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let compatibility = FakeTransport()
        let manager = self.makeManager(defaults: defaults, compatibilityTransport: compatibility)

        manager.sendMachineMatrix(names: ["windows", "Mac"], twoRow: false, swap: true)

        #expect(compatibility.calls.contains(.matrix(["WINDOWS", "MAC"], false, true)))
    }

    @Test func connectToHostUsesCorrectDefaultPortPerProtocolMode() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let modern = FakeTransport()
        let compatibility = FakeTransport()
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.messagePort = 15111
        let manager = self.makeManager(
            defaults: defaults,
            settings: settings,
            modernTransport: modern,
            compatibilityTransport: compatibility)

        manager.connectToHost(ip: "192.168.1.10")
        #expect(compatibility.calls.contains(.connectHost("192.168.1.10", 15111)))

        manager.protocolMode = .modern
        manager.connectToHost(ip: "192.168.1.20")
        #expect(modern.calls.contains(.connectHost("192.168.1.20", 12345)))
    }

    @Test func hideMouseEventCallsCursorControllerHide() async {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let compatibility = FakeTransport()
        let cursor = FakeCursorController()
        let manager = self.makeManager(
            defaults: defaults,
            compatibilityTransport: compatibility,
            cursorController: cursor)

        compatibility.emit(.hideMouse)
        await self.waitUntil { cursor.hideCount == 1 }
        _ = manager

        #expect(cursor.hideCount == 1)
        #expect(cursor.unhideCount == 0)
    }

    private func makeManager(
        localName: String = "Test Mac",
        defaults: UserDefaults,
        settings: MBCompatibilitySettings? = nil,
        modernTransport: FakeTransport = FakeTransport(),
        compatibilityTransport: FakeTransport = FakeTransport(),
        cursorController: FakeCursorController = FakeCursorController()
    ) -> MBNetworkManager {
        let pasteboard = FakePasteboard()
        let geometry = FakeScreenGeometry()
        let input = MBInputManager(
            pasteboard: pasteboard,
            synthesizer: FakeInputEventSynthesizer(),
            screenGeometry: geometry,
            startClipboardSync: false,
            observeAppLifecycle: false)
        return MBNetworkManager.testing(
            localName: localName,
            compatibilitySettings: settings ?? MBCompatibilitySettings(defaults: defaults),
            inputManager: input,
            modernTransport: modernTransport,
            compatibilityTransport: compatibilityTransport,
            pasteboard: pasteboard,
            screenGeometry: geometry,
            clock: FakeClock(),
            cursorController: cursorController,
            screenCapturer: FakeScreenCapturer())
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
