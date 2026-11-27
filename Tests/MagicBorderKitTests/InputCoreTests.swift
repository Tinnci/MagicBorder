import CoreGraphics
import Foundation
import Testing

@testable import MagicBorderKit

@Suite("InputCore")
@MainActor
struct InputCoreTests {
    @Test func mouseMoveSnapshotConvertsToRemoteMouseMove() {
        let event = MBRemoteEventConverter.convert(
            snapshot: makeEventSnapshot(type: .mouseMoved, location: CGPoint(x: 10, y: 20)))

        #expect(event?.type == .mouseMove)
        #expect(event?.point == CGPoint(x: 10, y: 20))
    }

    @Test func leftMouseDownSnapshotConvertsToRemoteClick() {
        let event = MBRemoteEventConverter.convert(
            snapshot: makeEventSnapshot(type: .leftMouseDown, location: CGPoint(x: 30, y: 40)))

        #expect(event?.type == .leftMouseDown)
        #expect(event?.point == CGPoint(x: 30, y: 40))
    }

    @Test func scrollSnapshotPreservesBothAxes() {
        let event = MBRemoteEventConverter.convert(
            snapshot: makeEventSnapshot(type: .scrollWheel, scrollDeltaY: -7, scrollDeltaX: 3))

        #expect(event?.type == .scrollWheel)
        #expect(event?.deltaY == -7)
        #expect(event?.deltaX == 3)
    }

    @Test func keySnapshotsPreserveKeyCodeAndDirection() {
        let keyDown = MBRemoteEventConverter.convert(
            snapshot: makeEventSnapshot(type: .keyDown, keyCode: 12))
        let keyUp = MBRemoteEventConverter.convert(
            snapshot: makeEventSnapshot(type: .keyUp, keyCode: 12))

        #expect(keyDown?.type == .keyDown)
        #expect(keyDown?.keyCode == 12)
        #expect(keyUp?.type == .keyUp)
        #expect(keyUp?.keyCode == 12)
    }

    @Test func flagsChangedSnapshotDoesNotCreateModernRemoteEvent() {
        let event = MBRemoteEventConverter.convert(
            snapshot: makeEventSnapshot(type: .flagsChanged, keyCode: 56, flags: .maskShift))

        #expect(event == nil)
    }

    @Test func keyCodeMapperCoversCommonBidirectionalMappings() {
        #expect(MBKeyCodeMapper.windowsKeyCode(for: 0) == 0x41)
        #expect(MBKeyCodeMapper.windowsKeyCode(for: 53) == 0x1B)
        #expect(MBKeyCodeMapper.windowsKeyCode(for: 9999) == nil)
        #expect(MBKeyCodeMapper.macKeyCode(forWindowsKeyCode: 0x41) == 0)
        #expect(MBKeyCodeMapper.macKeyCode(forWindowsKeyCode: 0x1B) == 53)
        #expect(MBKeyCodeMapper.macKeyCode(forWindowsKeyCode: 0x9999) == nil)
    }

    @Test func modifierDetectionChecksMatchingCGEventFlags() {
        #expect(MBKeyCodeMapper.isModifierDown(macKeyCode: 56, flags: .maskShift))
        #expect(!MBKeyCodeMapper.isModifierDown(macKeyCode: 56, flags: .maskCommand))
        #expect(MBKeyCodeMapper.isModifierDown(macKeyCode: 55, flags: .maskCommand))
        #expect(MBKeyCodeMapper.isModifierDown(macKeyCode: 58, flags: .maskAlternate))
    }

    @Test func virtualCursorTrackerAccumulatesClampsAndResets() {
        var tracker = MBVirtualCursorTracker()
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)

        let first = tracker.advance(startLocation: CGPoint(x: 500, y: 400), deltaX: 50, deltaY: -40, screenFrame: frame)
        #expect(first == CGPoint(x: 550, y: 360))

        let clamped = tracker.advance(startLocation: .zero, deltaX: 2000, deltaY: -1000, screenFrame: frame)
        #expect(clamped == CGPoint(x: 1000, y: 0))

        tracker.reset()
        #expect(tracker.position == nil)
    }

    @Test func inputManagerTracksRemoteTargetWithoutSharedSingleton() {
        let manager = MBInputManager(
            pasteboard: FakePasteboard(),
            synthesizer: FakeInputEventSynthesizer(),
            screenGeometry: FakeScreenGeometry(),
            startClipboardSync: false,
            observeAppLifecycle: false)
        let target = UUID()

        manager.setRemoteTarget(target)
        #expect(manager.currentRemoteID == target)

        manager.setRemoteTarget(nil)
        #expect(manager.currentRemoteID == nil)
    }
}
