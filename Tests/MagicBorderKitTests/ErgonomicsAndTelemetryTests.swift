import CoreGraphics
import Foundation
import Testing

@testable import MagicBorderKit

@Suite("ErgonomicsAndTelemetry")
@MainActor
struct ErgonomicsAndTelemetryTests {
    @Test func peerProfileStoreResolvesCaseInsensitiveOverridesAndPersists() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let store = MBPeerProfileStore(defaults: defaults)
        let fallback = PeerInputProfile(modifierRemapMode: .standard, invertRemoteScroll: false, remoteScrollSpeed: 1.0)

        #expect(store.profile(for: "WinPC", default: fallback) == fallback)
        #expect(!store.hasOverride(for: "WinPC"))

        let custom = PeerInputProfile(
            modifierRemapMode: .swapCommandControl,
            invertRemoteScroll: true,
            remoteScrollSpeed: 1.75)
        store.setOverride(custom, for: "  winpc  ")

        let reloaded = MBPeerProfileStore(defaults: defaults)
        #expect(reloaded.hasOverride(for: "WINPC"))
        #expect(reloaded.profile(for: "WinPC", default: fallback) == custom)

        reloaded.clearOverride(for: "winpc")
        #expect(!reloaded.hasOverride(for: "WINPC"))
    }

    @Test func customHotkeysPersistAndMatchLockAllScreensAction() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        var config = MBHotkeyConfiguration.default
        let customBinding = MBHotkeyBinding(keyCode: 12, flags: [.maskCommand, .maskShift])  // Cmd+Shift+Q
        config.toggleCursorLock = customBinding
        #expect(customBinding.displayLabel == "⇧⌘Q")

        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.hotkeys = config

        let reloaded = MBCompatibilitySettings(defaults: defaults)
        #expect(reloaded.hotkeys.toggleCursorLock == customBinding)

        #expect(
            MBShortcutMatcher.matchShortcut(
                keyCode: 12,
                flags: [.maskCommand, .maskShift],
                enabled: true,
                configuration: reloaded.hotkeys) == .toggleCursorLock)

        #expect(
            MBShortcutMatcher.matchShortcut(
                keyCode: 37,
                flags: [.maskControl, .maskAlternate, .maskCommand],
                enabled: true,
                configuration: .default) == .lockAllScreens)
    }

    @Test func networkManagerErgonomicsAndLockAllScreensOperateSafely() async {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let compatibility = FakeTransport()
        let pasteboard = FakePasteboard()
        pasteboard.storedString = "sync-now"
        let screenLocker = FakeScreenLocker()
        let geometry = FakeScreenGeometry()
        let input = MBInputManager(
            pasteboard: pasteboard,
            synthesizer: FakeInputEventSynthesizer(),
            screenGeometry: geometry,
            startClipboardSync: false,
            observeAppLifecycle: false)

        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.securityKey = "MyTopSecret12345"

        let manager = MBNetworkManager.testing(
            localName: "Mac",
            compatibilitySettings: settings,
            inputManager: input,
            compatibilityTransport: compatibility,
            pasteboard: pasteboard,
            screenGeometry: geometry,
            clock: FakeClock(),
            cursorController: FakeCursorController(),
            screenCapturer: FakeScreenCapturer(),
            screenLocker: screenLocker)

        let peer = Machine(id: UUID(), name: "WinHost", state: .connected, mwbPeerID: 88)
        compatibility.emit(.machineConnected(peer))
        await Self.waitUntil { manager.connectedMachines.count == 1 }

        let telemetry = PeerTelemetry(
            messageChannelConnected: true,
            clipboardChannelConnected: true,
            lastHeartbeatAt: Date(),
            rttMs: 4)
        compatibility.emit(.peerTelemetryUpdated(peer.id, telemetry))
        await Self.waitUntil { manager.peerTelemetry[peer.id]?.rttMs == 4 }
        #expect(manager.peerTelemetry[peer.id] == telemetry)

        manager.handleShortcut(.toggleCursorLock)
        #expect(manager.isCursorLocked)
        manager.handleShortcut(.toggleCursorLock)
        #expect(!manager.isCursorLocked)

        manager.handleShortcut(.toggleInputPause)
        #expect(manager.isInputPaused)
        manager.handleShortcut(.toggleInputPause)
        #expect(!manager.isInputPaused)

        manager.handleShortcut(.switchToSlot(1))
        #expect(compatibility.calls.contains(.activate(peer.id)))

        manager.pushCurrentClipboard()
        #expect(
            compatibility.calls.contains { call in
                if case .clipboardText("sync-now", _) = call { return true }
                return false
            })

        manager.appendPairingLog("Using key MyTopSecret12345")
        let redacted = manager.redactedDiagnosticsText()
        #expect(!redacted.contains("MyTopSecret12345"))
        #expect(redacted.contains("[REDACTED]"))

        manager.handleShortcut(.lockAllScreens)
        #expect(compatibility.calls.contains(.lockScreen))
        #expect(screenLocker.lockCount == 1)
        #expect(manager.toast == .lockedAllScreens)

        manager.handleSystemSleepOrLock()
        _ = manager.localIPv4Addresses()
    }

    @Test func mwbTransportAppliesPerPeerProfileScrollModifierSwapAndLockScreen() async {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let settings = MBCompatibilitySettings(defaults: defaults)
        let service = FakeMWBCompatibilityService()
        let transport = MBMWBTransport(
            localName: "Mac",
            localID: 1,
            settings: settings,
            service: service,
            screenGeometry: FakeScreenGeometry(),
            clock: FakeClock())

        let profile = PeerInputProfile(
            modifierRemapMode: .swapCommandControl,
            invertRemoteScroll: true,
            remoteScrollSpeed: 2.0)
        transport.resolveInputProfile = { _ in profile }

        let peerID = UUID()
        // Cmd keyDown -> Ctrl (0x11)
        transport.sendRemoteInput(
            snapshot: makeEventSnapshot(type: .keyDown, keyCode: 55),
            activeMachineId: peerID)
        #expect(service.sentKeyEvents.contains(MWBKeyEvent(keyCode: 0x11, flags: 0)))

        // Inverted 2x scroll wheel
        transport.sendRemoteInput(
            snapshot: makeEventSnapshot(type: .scrollWheel, scrollDeltaY: 3),
            activeMachineId: peerID)
        #expect(service.sentMouseEvents.contains(MWBMouseEvent(x: 0, y: 0, wheel: -6, flags: 0x20A)))

        // Middle mouse click + lock screen releases modifiers
        transport.sendRemoteInput(
            snapshot: makeEventSnapshot(type: .otherMouseDown, location: CGPoint(x: 100, y: 100)),
            activeMachineId: peerID)
        #expect(service.sentMouseEvents.contains { $0.flags == 0x207 })

        transport.sendLockScreen()
        #expect(service.sendLockScreenCount == 1)
        #expect(service.sentKeyEvents.contains(MWBKeyEvent(keyCode: 0x5B, flags: 0x80)))
    }

    private static func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
