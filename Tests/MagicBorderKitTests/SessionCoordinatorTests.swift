import CoreGraphics
import Foundation
import Testing

@testable import MagicBorderKit

@Suite("SessionCoordinator")
@MainActor
struct SessionCoordinatorTests {
    @Test func manualModernSwitchSetsActiveMachineAndRemoteTarget() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        var remoteTarget: UUID?
        let coordinator = self.makeCoordinator(
            machines: [remote],
            isMWBMode: false,
            defaults: defaults,
            updateRemoteTarget: { remoteTarget = $0 })

        coordinator.requestSwitch(to: remote.id)

        #expect(coordinator.activeMachineId == remote.id)
        #expect(coordinator.activeMachineName == "Windows")
        #expect(remoteTarget == remote.id)
        #expect(coordinator.switchState == .active)
    }

    @Test func forceReturnToLocalClearsRemoteTargetAndLogsReason() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        var remoteTarget: UUID?
        var logs: [String] = []
        let coordinator = self.makeCoordinator(
            machines: [remote],
            isMWBMode: false,
            defaults: defaults,
            updateRemoteTarget: { remoteTarget = $0 },
            appendLog: { logs.append($0) })
        coordinator.requestSwitch(to: remote.id)

        coordinator.forceReturnToLocal(reason: "test")

        #expect(coordinator.activeMachineId == nil)
        #expect(remoteTarget == nil)
        #expect(coordinator.activeMachineName == "Mac")
        #expect(logs.contains("Force return to local (test)"))
    }

    @Test func manualMWBSwitchActivatesCompatibilityMachineAndCentersCursor() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        var activated: UUID?
        var didCenter = false
        let coordinator = self.makeCoordinator(
            machines: [remote],
            isMWBMode: true,
            defaults: defaults,
            activateCompatibilityMachine: { activated = $0?.id },
            centerRemoteCursor: { didCenter = true })

        coordinator.requestSwitch(to: remote.id)

        #expect(coordinator.switchState == .switching)
        #expect(activated == remote.id)
        #expect(didCenter)
    }

    @Test func requestSwitchToLocalNameReturnsFromRemote() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        var remoteTarget: UUID?
        let coordinator = self.makeCoordinator(
            machines: [remote],
            isMWBMode: false,
            defaults: defaults,
            updateRemoteTarget: { remoteTarget = $0 })
        coordinator.requestSwitch(to: remote.id)

        coordinator.requestSwitch(toMachineNamed: " mac ")

        #expect(coordinator.activeMachineId == nil)
        #expect(remoteTarget == nil)
        #expect(coordinator.activeMachineName == "Mac")
    }

    @Test func unknownManualSwitchLeavesStateUnchanged() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        let coordinator = self.makeCoordinator(machines: [remote], isMWBMode: false, defaults: defaults)

        coordinator.requestSwitch(toMachineNamed: "Unknown")

        #expect(coordinator.activeMachineId == nil)
        #expect(coordinator.switchState == .idle)
    }

    @Test func mwbManualSwitchDoesNotCenterCursorWhenRelativeMouseIsEnabled() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.moveMouseRelatively = true
        var didCenter = false
        let coordinator = self.makeCoordinator(
            machines: [remote],
            isMWBMode: true,
            settings: settings,
            defaults: defaults,
            centerRemoteCursor: { didCenter = true })

        coordinator.requestSwitch(to: remote.id)

        #expect(!didCenter)
    }

    @Test func transportActiveMachineNilUnhidesCursor() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        let cursor = FakeCursorController()
        let coordinator = self.makeCoordinator(
            machines: [remote],
            isMWBMode: false,
            defaults: defaults,
            cursorController: cursor)
        coordinator.setActiveMachine(remote.id, notify: false)

        coordinator.handleTransportActiveMachineChanged(id: nil, name: nil)

        #expect(coordinator.activeMachineId == nil)
        #expect(cursor.unhideCount == 1)
    }

    @Test func localRightEdgeSwitchTriggersAndRespectsCornerBlocking() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.blockCorners = true
        let clock = FakeClock(now: 100)
        let geometry = FakeScreenGeometry(mainScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let coordinator = self.makeCoordinator(
            machines: [remote],
            isMWBMode: false,
            settings: settings,
            defaults: defaults,
            screenGeometry: geometry,
            clock: clock)

        // Corner should be ignored when blockCorners = true.
        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 1920, y: 0)))
        #expect(coordinator.activeMachineId == nil)

        // Non-corner right edge should switch to remote.
        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 1920, y: 540)))
        #expect(coordinator.activeMachineId == remote.id)
    }

    @Test func remoteCenterMouseMovesDoNotSelfLockEdgeReturn() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.edgeSwitchLockSeconds = 0.4
        settings.edgeSwitchSafeMargin = 16
        let clock = FakeClock(now: 100)
        let geometry = FakeScreenGeometry(mainScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let coordinator = self.makeCoordinator(
            machines: [remote],
            isMWBMode: false,
            settings: settings,
            defaults: defaults,
            screenGeometry: geometry,
            clock: clock)

        // Switch via right edge -> locks for 0.4s + pending release.
        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 1920, y: 540)))
        #expect(coordinator.activeMachineId == remote.id)

        // Advance time past lock and send center mouse moves while remote is active.
        clock.advance(by: 1.0)
        coordinator.handleRemoteMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 960, y: 540)))
        // Immediately moving back to left edge (same timestamp!) must NOT be blocked by center moves.
        coordinator.handleRemoteMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 0, y: 540)))

        #expect(coordinator.activeMachineId == nil)
        #expect(coordinator.switchState == .idle)
    }

    private func makeCoordinator(
        machines: [Machine],
        isMWBMode: Bool,
        settings: MBCompatibilitySettings? = nil,
        defaults: UserDefaults,
        screenGeometry: FakeScreenGeometry = FakeScreenGeometry(),
        clock: FakeClock = FakeClock(),
        cursorController: FakeCursorController = FakeCursorController(),
        updateRemoteTarget: @escaping (UUID?) -> Void = { _ in },
        appendLog: @escaping (String) -> Void = { _ in },
        activateCompatibilityMachine: @escaping (Machine?) -> Void = { _ in },
        centerRemoteCursor: @escaping () -> Void = {}
    ) -> MBSessionCoordinator {
        let resolvedSettings = settings ?? MBCompatibilitySettings(defaults: defaults)
        let dependencies = MBSessionCoordinator.Dependencies(
            connectedMachines: { machines },
            arrangement: {
                MachineArrangement(
                    slots: [MBNetworkManager.localMachineUUID] + machines.map(\.id),
                    columns: max(1, machines.count + 1))
            },
            settings: { resolvedSettings },
            updateRemoteTarget: updateRemoteTarget,
            emitToast: { _ in },
            appendLog: appendLog,
            activateRemoteMachine: { machine in
                guard isMWBMode else { return false }
                activateCompatibilityMachine(machine)
                return true
            },
            centerRemoteCursor: centerRemoteCursor)

        return MBSessionCoordinator(
            localMachineID: MBNetworkManager.localMachineUUID,
            localMachineName: "Mac",
            dependencies: dependencies,
            screenGeometry: screenGeometry,
            clock: clock,
            cursorController: cursorController)
    }
}
