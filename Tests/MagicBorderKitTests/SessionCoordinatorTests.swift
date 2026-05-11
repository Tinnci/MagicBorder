import AppKit
@testable import MagicBorderKit
import XCTest

@MainActor
final class SessionCoordinatorTests: XCTestCase {
    func testManualModernSwitchSetsActiveMachineAndRemoteTarget() {
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        var remoteTarget: UUID?
        let coordinator = self.makeCoordinator(
            machines: [remote],
            protocolMode: .modern,
            updateRemoteTarget: { remoteTarget = $0 })

        coordinator.requestSwitch(to: remote.id)

        XCTAssertEqual(coordinator.activeMachineId, remote.id)
        XCTAssertEqual(coordinator.activeMachineName, "Windows")
        XCTAssertEqual(remoteTarget, remote.id)
        XCTAssertEqual(coordinator.switchState, .active)
    }

    func testForceReturnToLocalClearsRemoteTargetAndLogsReason() {
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        var remoteTarget: UUID?
        var logs: [String] = []
        let coordinator = self.makeCoordinator(
            machines: [remote],
            protocolMode: .modern,
            updateRemoteTarget: { remoteTarget = $0 },
            appendLog: { logs.append($0) })
        coordinator.requestSwitch(to: remote.id)

        coordinator.forceReturnToLocal(reason: "test")

        XCTAssertNil(coordinator.activeMachineId)
        XCTAssertNil(remoteTarget)
        XCTAssertEqual(coordinator.activeMachineName, "Mac")
        XCTAssertTrue(logs.contains("Force return to local (test)"))
    }

    func testManualMWBSwitchActivatesCompatibilityMachineAndCentersCursor() {
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        var activated: UUID?
        var didCenter = false
        let coordinator = self.makeCoordinator(
            machines: [remote],
            protocolMode: .mwbCompatibility,
            activateCompatibilityMachine: { activated = $0?.id },
            centerRemoteCursor: { didCenter = true })

        coordinator.requestSwitch(to: remote.id)

        XCTAssertEqual(coordinator.switchState, .switching)
        XCTAssertEqual(activated, remote.id)
        XCTAssertTrue(didCenter)
    }

    func testRequestSwitchToLocalNameReturnsFromRemote() {
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        var remoteTarget: UUID?
        let coordinator = self.makeCoordinator(
            machines: [remote],
            protocolMode: .modern,
            updateRemoteTarget: { remoteTarget = $0 })
        coordinator.requestSwitch(to: remote.id)

        coordinator.requestSwitch(toMachineNamed: " mac ")

        XCTAssertNil(coordinator.activeMachineId)
        XCTAssertNil(remoteTarget)
        XCTAssertEqual(coordinator.activeMachineName, "Mac")
    }

    func testUnknownManualSwitchLeavesStateUnchanged() {
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        let coordinator = self.makeCoordinator(machines: [remote], protocolMode: .modern)

        coordinator.requestSwitch(toMachineNamed: "Unknown")

        XCTAssertNil(coordinator.activeMachineId)
        XCTAssertEqual(coordinator.switchState, .idle)
    }

    func testMWBManualSwitchDoesNotCenterCursorWhenRelativeMouseIsEnabled() {
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        let settings = MBCompatibilitySettings(defaults: UserDefaults(suiteName: "MagicBorderTests.\(UUID().uuidString)")!)
        settings.moveMouseRelatively = true
        var didCenter = false
        let coordinator = self.makeCoordinator(
            machines: [remote],
            protocolMode: .mwbCompatibility,
            settings: settings,
            centerRemoteCursor: { didCenter = true })

        coordinator.requestSwitch(to: remote.id)

        XCTAssertFalse(didCenter)
    }

    func testTransportActiveMachineNilUnhidesCursor() {
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        var didUnhide = false
        let coordinator = self.makeCoordinator(
            machines: [remote],
            protocolMode: .modern,
            unhideCursor: { didUnhide = true })
        coordinator.setActiveMachine(remote.id, notify: false)

        coordinator.handleTransportActiveMachineChanged(id: nil, name: nil)

        XCTAssertNil(coordinator.activeMachineId)
        XCTAssertTrue(didUnhide)
    }

    private func makeCoordinator(
        machines: [Machine],
        protocolMode: MBProtocolMode,
        settings: MBCompatibilitySettings = MBCompatibilitySettings(defaults: UserDefaults(suiteName: "MagicBorderTests.\(UUID().uuidString)")!),
        updateRemoteTarget: @escaping (UUID?) -> Void = { _ in },
        appendLog: @escaping (String) -> Void = { _ in },
        activateCompatibilityMachine: @escaping (Machine?) -> Void = { _ in },
        centerRemoteCursor: @escaping () -> Void = {},
        unhideCursor: @escaping () -> Void = {})
        -> MBSessionCoordinator
    {
        MBSessionCoordinator(
            localMachineID: MBNetworkManager.localMachineUUID,
            localMachineName: "Mac",
            connectedMachinesProvider: { machines },
            arrangementProvider: {
                MachineArrangement(
                    slots: [MBNetworkManager.localMachineUUID] + machines.map(\.id),
                    columns: max(1, machines.count + 1))
            },
            settingsProvider: { settings },
            protocolModeProvider: { protocolMode },
            updateRemoteTarget: updateRemoteTarget,
            showToast: { _, _ in },
            appendLog: appendLog,
            activateCompatibilityMachine: activateCompatibilityMachine,
            centerRemoteCursor: centerRemoteCursor,
            unhideCursor: unhideCursor)
    }
}
