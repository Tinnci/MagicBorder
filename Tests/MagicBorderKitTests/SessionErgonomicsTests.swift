import CoreGraphics
import Foundation
import Testing

@testable import MagicBorderKit

@Suite("SessionErgonomics")
@MainActor
struct SessionErgonomicsTests {
    @Test func multiMonitorSeamDoesNotSwitchWhileOuterEdgeSwitches() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let geometry = FakeScreenGeometry(mainScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        geometry.allScreenFrames = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        ]

        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        var target: UUID?
        let coordinator = self.makeCoordinator(
            remote: remote,
            defaults: defaults,
            geometry: geometry,
            updateRemoteTarget: { target = $0 })

        // Right edge of display 1 touches display 2 (internal seam) -> stays local.
        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 1919, y: 500)))
        #expect(target == nil)

        // Outer right edge of display 2 -> switches to remote.
        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 3839, y: 500)))
        #expect(target == remote.id)
    }

    @Test func cursorLockAndPausedStatesPreventEdgeSwitch() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        var target: UUID?
        var toasts: [MBToastEvent] = []
        let coordinator = self.makeCoordinator(
            remote: remote,
            defaults: defaults,
            updateRemoteTarget: { target = $0 },
            emitToast: { toasts.append($0) })

        coordinator.toggleCursorLock()
        #expect(coordinator.isCursorLocked)
        #expect(toasts.last == .cursorLocked)

        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 1919, y: 500)))
        #expect(target == nil)

        coordinator.toggleCursorLock()
        #expect(!coordinator.isCursorLocked)
        #expect(toasts.last == .cursorUnlocked)

        coordinator.isInputPaused = true
        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 1919, y: 500)))
        #expect(target == nil)

        coordinator.isInputPaused = false
        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 1919, y: 500)))
        #expect(target == remote.id)
    }

    @Test func modifierGateDwellDelayAndFullscreenAutoLockControlSwitching() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.edgeCrossingModifier = .option
        settings.edgeDwellSeconds = 0.25
        settings.lockCursorInFullscreenApps = true

        let clock = FakeClock(now: 100)
        var fullscreenActive = true
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)
        var target: UUID?
        let coordinator = self.makeCoordinator(
            remote: remote,
            settings: settings,
            defaults: defaults,
            clock: clock,
            isFullscreen: { fullscreenActive },
            updateRemoteTarget: { target = $0 })

        // Blocked by fullscreen.
        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 1919, y: 500), flags: .maskAlternate))
        #expect(target == nil)

        // Blocked by missing Option key.
        fullscreenActive = false
        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 1919, y: 500), flags: []))
        #expect(target == nil)

        // First sample at edge starts dwell timer.
        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 1919, y: 500), flags: .maskAlternate))
        #expect(target == nil)

        // Before dwell completes.
        clock.advance(by: 0.1)
        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 1919, y: 500), flags: .maskAlternate))
        #expect(target == nil)

        // After dwell elapses.
        clock.advance(by: 0.2)
        coordinator.handleLocalMouseEvent(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 1919, y: 500), flags: .maskAlternate))
        #expect(target == remote.id)
    }

    private func makeCoordinator(
        remote: Machine,
        settings: MBCompatibilitySettings? = nil,
        defaults: UserDefaults,
        geometry: FakeScreenGeometry = FakeScreenGeometry(),
        clock: FakeClock = FakeClock(),
        isFullscreen: @escaping () -> Bool = { false },
        updateRemoteTarget: @escaping (UUID?) -> Void = { _ in },
        emitToast: @escaping (MBToastEvent) -> Void = { _ in }
    ) -> MBSessionCoordinator {
        let resolvedSettings = settings ?? MBCompatibilitySettings(defaults: defaults)
        return MBSessionCoordinator(
            localMachineID: MBNetworkManager.localMachineUUID,
            localMachineName: "Mac",
            dependencies: MBSessionCoordinator.Dependencies(
                connectedMachines: { [remote] },
                arrangement: { MachineArrangement(slots: [MBNetworkManager.localMachineUUID, remote.id], columns: 2) },
                settings: { resolvedSettings },
                updateRemoteTarget: updateRemoteTarget,
                emitToast: emitToast,
                appendLog: { _ in },
                activateRemoteMachine: { _ in false },
                centerRemoteCursor: {},
                isFrontmostAppFullscreen: isFullscreen),
            screenGeometry: geometry,
            clock: clock,
            cursorController: FakeCursorController())
    }
}
