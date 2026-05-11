import Foundation
@testable import MagicBorderKit
import XCTest

@MainActor
final class NetworkManagerTests: XCTestCase {
    func testTransportMachineEventsUpdateConnectionStateAndRecoverActiveMachineOnDisconnect() async {
        let compatibility = FakeTransport()
        let manager = MBNetworkManager.testing(
            localName: "Local Mac",
            compatibilityTransport: compatibility)
        let remote = Machine(id: UUID(), name: "Windows", state: .connected, mwbPeerID: 42)

        compatibility.emit(.machineConnected(remote))
        await self.waitUntil { manager.connectedMachines.map(\.id) == [remote.id] }
        XCTAssertEqual(manager.connectedMachines.map(\.id), [remote.id])

        compatibility.emit(.activeMachineChanged(remote.id, remote.name))
        await self.waitUntil { manager.activeMachineId == remote.id }
        XCTAssertEqual(manager.activeMachineId, remote.id)

        compatibility.emit(.machineDisconnected(remote.id))
        await self.waitUntil { manager.activeMachineId == nil && manager.connectedMachines.isEmpty }
        XCTAssertNil(manager.activeMachineId)
        XCTAssertTrue(manager.connectedMachines.isEmpty)
    }

    func testApplyCompatibilitySettingsUpdatesCurrentTransport() {
        let compatibility = FakeTransport()
        let settings = MBCompatibilitySettings(defaults: UserDefaults(suiteName: "MagicBorderTests.\(UUID().uuidString)")!)
        settings.securityKey = "1234567890ABCDEF"
        settings.messagePort = 15111
        settings.clipboardPort = 15110
        let manager = MBNetworkManager.testing(
            compatibilitySettings: settings,
            compatibilityTransport: compatibility)

        manager.applyCompatibilitySettings()

        XCTAssertTrue(
            compatibility.calls.contains(
                .updateConfiguration(
                    securityKey: "1234567890ABCDEF",
                    messagePort: 15111,
                    clipboardPort: 15110)))
    }

    func testSendFileDropIsGatedByTransferFilesSetting() {
        let compatibility = FakeTransport()
        let settings = MBCompatibilitySettings(defaults: UserDefaults(suiteName: "MagicBorderTests.\(UUID().uuidString)")!)
        settings.transferFiles = false
        let manager = MBNetworkManager.testing(
            compatibilitySettings: settings,
            compatibilityTransport: compatibility)

        let sent = manager.sendFileDrop([URL(fileURLWithPath: "/tmp/file.txt")])

        XCTAssertFalse(sent)
        XCTAssertFalse(compatibility.calls.contains { call in
            if case .fileDrop = call { return true }
            return false
        })
    }

    func testSendFileDropUsesCurrentTransportWhenEnabled() {
        let compatibility = FakeTransport()
        let settings = MBCompatibilitySettings(defaults: UserDefaults(suiteName: "MagicBorderTests.\(UUID().uuidString)")!)
        settings.transferFiles = true
        let manager = MBNetworkManager.testing(
            compatibilitySettings: settings,
            compatibilityTransport: compatibility)
        let url = URL(fileURLWithPath: "/tmp/file.txt")

        let sent = manager.sendFileDrop([url])

        XCTAssertTrue(sent)
        XCTAssertTrue(compatibility.calls.contains(.fileDrop([url])))
    }

    func testArrangementSyncSendsVisibleMachineNamesInArrangementOrder() async {
        let compatibility = FakeTransport()
        let manager = MBNetworkManager.testing(
            localName: "Mac",
            compatibilityTransport: compatibility)
        let first = Machine(id: UUID(), name: "Windows", state: .connected)
        let second = Machine(id: UUID(), name: "Linux", state: .connected)
        compatibility.emit(.machineConnected(first))
        compatibility.emit(.machineConnected(second))
        await self.waitUntil { manager.connectedMachines.count == 2 }

        manager.syncArrangement(machineIDs: [second.id, MBNetworkManager.localMachineUUID, first.id], twoRow: true, swap: false)

        XCTAssertTrue(compatibility.calls.contains(.matrix(["LINUX", "MAC", "WINDOWS"], true, false)))
    }

    func testTransportLogAndErrorUpdatePairingDiagnostics() async {
        let compatibility = FakeTransport()
        let manager = MBNetworkManager.testing(compatibilityTransport: compatibility)

        compatibility.emit(.log("hello"))
        await self.waitUntil { manager.pairingDebugLog.contains { $0.contains("hello") } }
        compatibility.emit(.error("bad key"))
        await self.waitUntil { manager.pairingError == "bad key" }

        XCTAssertEqual(manager.pairingError, "bad key")
        XCTAssertTrue(manager.pairingDebugLog.contains { $0.contains("ERROR: bad key") })
    }

    func testArrangementOptionsEventUpdatesCompatibilitySettings() async {
        let compatibility = FakeTransport()
        let manager = MBNetworkManager.testing(compatibilityTransport: compatibility)

        compatibility.emit(.arrangementOptionsUpdated(twoRow: true, swap: true))
        await self.waitUntil {
            manager.compatibilitySettings.matrixOneRow == false
                && manager.compatibilitySettings.matrixCircle == true
        }

        XCTAssertFalse(manager.compatibilitySettings.matrixOneRow)
        XCTAssertTrue(manager.compatibilitySettings.matrixCircle)
    }

    func testSendMachineMatrixUppercasesNamesBeforeSending() {
        let compatibility = FakeTransport()
        let manager = MBNetworkManager.testing(compatibilityTransport: compatibility)

        manager.sendMachineMatrix(names: ["windows", "Mac"], twoRow: false, swap: true)

        XCTAssertTrue(compatibility.calls.contains(.matrix(["WINDOWS", "MAC"], false, true)))
    }

    func testConnectToHostUsesCurrentTransport() {
        let compatibility = FakeTransport()
        let manager = MBNetworkManager.testing(compatibilityTransport: compatibility)

        manager.connectToHost(ip: "192.168.1.10", port: 15101)

        XCTAssertTrue(compatibility.calls.contains(.connectHost("192.168.1.10", 15101)))
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool)
        async
    {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
