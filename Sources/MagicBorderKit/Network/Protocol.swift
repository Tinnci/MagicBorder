import CoreGraphics
import Foundation

// MARK: - Packet Types

public enum PacketType: Codable, Sendable {
    case handshake(info: MachineInfo)
    case inputEvent(RemoteEvent)
    case clipboardData(ClipboardPayload)
    case heartbeat
    case bye
}

// MARK: - Payloads

public struct MachineInfo: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let screenWidth: Double
    public let screenHeight: Double
    public var signature: String?  // HMAC(securityKey, id.uuidString)

    public init(
        id: UUID, name: String, screenWidth: Double, screenHeight: Double, signature: String? = nil
    ) {
        self.id = id
        self.name = name
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.signature = signature
    }
}

public struct ClipboardPayload: Codable, Sendable {
    public let content: Data
    public let type: ClipboardType
}

public enum ClipboardType: Codable, Sendable {
    case text
    case image
}

// MARK: - Input Events

public enum RemoteEventType: Codable, Sendable {
    case mouseMove
    case leftMouseDown, leftMouseUp
    case rightMouseDown, rightMouseUp
    case scrollWheel
    case keyDown, keyUp
}

public struct RemoteEvent: Codable, Sendable {
    public let type: RemoteEventType
    public let point: CGPoint?  // For mouse events
    public let keyCode: CGKeyCode?  // For key events
    public let deltaX: Int?  // For Scroll
    public let deltaY: Int?  // For Scroll

    public init(
        type: RemoteEventType, point: CGPoint?, keyCode: CGKeyCode?, deltaX: Int?, deltaY: Int?
    ) {
        self.type = type
        self.point = point
        self.keyCode = keyCode
        self.deltaX = deltaX
        self.deltaY = deltaY
    }

    // Helper init for Mouse Move
    public static func mouseMove(at point: CGPoint) -> RemoteEvent {
        return RemoteEvent(type: .mouseMove, point: point, keyCode: nil, deltaX: nil, deltaY: nil)
    }

    // Helper init for Click
    public static func mouseClick(type: RemoteEventType, at point: CGPoint) -> RemoteEvent {
        return RemoteEvent(type: type, point: point, keyCode: nil, deltaX: nil, deltaY: nil)
    }

    public static func key(type: RemoteEventType, code: CGKeyCode) -> RemoteEvent {
        return RemoteEvent(type: type, point: nil, keyCode: code, deltaX: nil, deltaY: nil)
    }
}

// MARK: - Local Event Snapshot (Sendable)

public struct EventSnapshot: Sendable {
    public let location: CGPoint
    public let type: CGEventType
    public let keyCode: Int64
    public let scrollDeltaY: Int64
    public let scrollDeltaX: Int64
    public let flags: CGEventFlags

    public init(from event: CGEvent, type: CGEventType) {
        self.location = event.location
        self.type = type
        self.keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        self.scrollDeltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        self.scrollDeltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        self.flags = event.flags
    }
}
