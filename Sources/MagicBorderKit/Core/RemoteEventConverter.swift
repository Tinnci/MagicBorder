import CoreGraphics

/// Converts local `EventSnapshot` instances into Modern-protocol `RemoteEvent` payloads.
public enum MBRemoteEventConverter: Sendable {
    public static func convert(snapshot: EventSnapshot) -> RemoteEvent? {
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
                deltaX: Int(snapshot.scrollDeltaX),
                deltaY: Int(snapshot.scrollDeltaY))
        case .keyDown:
            RemoteEvent.key(type: .keyDown, code: CGKeyCode(snapshot.keyCode))
        case .keyUp:
            RemoteEvent.key(type: .keyUp, code: CGKeyCode(snapshot.keyCode))
        default:
            nil
        }
    }
}
