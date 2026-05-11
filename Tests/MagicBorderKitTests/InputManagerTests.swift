import CoreGraphics
@testable import MagicBorderKit
import XCTest

@MainActor
final class InputManagerTests: XCTestCase {
    func testMouseMoveSnapshotConvertsToRemoteMouseMove() {
        let event = MBInputManager.shared.convertToRemoteEvent(
            snapshot: self.snapshot(type: .mouseMoved, location: CGPoint(x: 10, y: 20)))

        XCTAssertEqual(event?.type, .mouseMove)
        XCTAssertEqual(event?.point, CGPoint(x: 10, y: 20))
    }

    func testLeftMouseDownSnapshotConvertsToRemoteClick() {
        let event = MBInputManager.shared.convertToRemoteEvent(
            snapshot: self.snapshot(type: .leftMouseDown, location: CGPoint(x: 30, y: 40)))

        XCTAssertEqual(event?.type, .leftMouseDown)
        XCTAssertEqual(event?.point, CGPoint(x: 30, y: 40))
    }

    func testScrollSnapshotPreservesBothAxes() {
        let event = MBInputManager.shared.convertToRemoteEvent(
            snapshot: self.snapshot(type: .scrollWheel, scrollDeltaY: -7, scrollDeltaX: 3))

        XCTAssertEqual(event?.type, .scrollWheel)
        XCTAssertEqual(event?.deltaY, -7)
        XCTAssertEqual(event?.deltaX, 3)
    }

    func testKeySnapshotsPreserveKeyCodeAndDirection() {
        let keyDown = MBInputManager.shared.convertToRemoteEvent(
            snapshot: self.snapshot(type: .keyDown, keyCode: 12))
        let keyUp = MBInputManager.shared.convertToRemoteEvent(
            snapshot: self.snapshot(type: .keyUp, keyCode: 12))

        XCTAssertEqual(keyDown?.type, .keyDown)
        XCTAssertEqual(keyDown?.keyCode, 12)
        XCTAssertEqual(keyUp?.type, .keyUp)
        XCTAssertEqual(keyUp?.keyCode, 12)
    }

    func testFlagsChangedSnapshotDoesNotCreateModernRemoteEvent() {
        let event = MBInputManager.shared.convertToRemoteEvent(
            snapshot: self.snapshot(type: .flagsChanged, keyCode: 56, flags: .maskShift))

        XCTAssertNil(event)
    }

    func testWindowsKeyCodeMappingCoversCommonMacKeys() {
        XCTAssertEqual(MBInputManager.shared.windowsKeyCode(for: 0), 0x41)
        XCTAssertEqual(MBInputManager.shared.windowsKeyCode(for: 53), 0x1B)
        XCTAssertNil(MBInputManager.shared.windowsKeyCode(for: 9999))
    }

    private func snapshot(
        type: CGEventType,
        location: CGPoint = .zero,
        keyCode: Int64 = 0,
        scrollDeltaY: Int64 = 0,
        scrollDeltaX: Int64 = 0,
        flags: CGEventFlags = [])
        -> EventSnapshot
    {
        EventSnapshot(
            location: location,
            type: type,
            keyCode: keyCode,
            scrollDeltaY: scrollDeltaY,
            scrollDeltaX: scrollDeltaX,
            mouseDeltaX: 0,
            mouseDeltaY: 0,
            flags: flags)
    }
}
