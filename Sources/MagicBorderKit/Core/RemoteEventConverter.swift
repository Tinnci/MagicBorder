import CoreGraphics

/// Converts local `EventSnapshot` instances into Modern-protocol `RemoteEvent` payloads.
public enum MBRemoteEventConverter: Sendable {
    public static func convert(
        snapshot: EventSnapshot,
        invertScroll: Bool = false,
        scrollSpeed: Double = 1.0
    ) -> RemoteEvent? {
        switch snapshot.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            RemoteEvent.mouseMove(at: snapshot.location)
        case .leftMouseDown:
            RemoteEvent.mouseClick(type: .leftMouseDown, at: snapshot.location)
        case .leftMouseUp:
            RemoteEvent.mouseClick(type: .leftMouseUp, at: snapshot.location)
        case .rightMouseDown:
            RemoteEvent.mouseClick(type: .rightMouseDown, at: snapshot.location)
        case .rightMouseUp:
            RemoteEvent.mouseClick(type: .rightMouseUp, at: snapshot.location)
        case .scrollWheel:
            RemoteEvent(
                type: .scrollWheel,
                point: nil,
                keyCode: nil,
                deltaX: Self.scaledScroll(snapshot.scrollDeltaX, invert: invertScroll, speed: scrollSpeed),
                deltaY: Self.scaledScroll(snapshot.scrollDeltaY, invert: invertScroll, speed: scrollSpeed))
        case .keyDown:
            RemoteEvent.key(type: .keyDown, code: CGKeyCode(snapshot.keyCode))
        case .keyUp:
            RemoteEvent.key(type: .keyUp, code: CGKeyCode(snapshot.keyCode))
        default:
            nil
        }
    }

    private static func scaledScroll(_ raw: Int64, invert: Bool, speed: Double) -> Int {
        guard raw != 0 else { return 0 }
        let clampedSpeed = max(0.25, min(3.0, speed))
        let sign: Double = invert ? -1.0 : 1.0
        let scaled = Int((Double(raw) * clampedSpeed * sign).rounded())
        if scaled == 0 {
            return raw > 0 ? (invert ? -1 : 1) : (invert ? 1 : -1)
        }
        return scaled
    }
}
