public import CoreGraphics
public import Foundation

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
    public var signature: String?

    public init(
        id: UUID,
        name: String,
        screenWidth: Double,
        screenHeight: Double,
        signature: String? = nil
    ) {
        self.id = id
        self.name = name
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.signature = signature
    }
}

public struct ClipboardPayload: Codable, Equatable, Sendable {
    public let content: Data
    public let type: ClipboardType

    public init(content: Data, type: ClipboardType) {
        self.content = content
        self.type = type
    }
}

public enum ClipboardType: Codable, Equatable, Sendable {
    case text
    case image
}

// MARK: - Input Events

public enum RemoteEventType: Codable, Equatable, Sendable {
    case mouseMove
    case leftMouseDown
    case leftMouseUp
    case rightMouseDown
    case rightMouseUp
    case scrollWheel
    case keyDown
    case keyUp
}

public struct RemoteEvent: Codable, Equatable, Sendable {
    public let type: RemoteEventType
    public let point: CGPoint?
    public let keyCode: CGKeyCode?
    public let deltaX: Int?
    public let deltaY: Int?

    public init(
        type: RemoteEventType,
        point: CGPoint?,
        keyCode: CGKeyCode?,
        deltaX: Int?,
        deltaY: Int?
    ) {
        self.type = type
        self.point = point
        self.keyCode = keyCode
        self.deltaX = deltaX
        self.deltaY = deltaY
    }

    public static func mouseMove(at point: CGPoint) -> RemoteEvent {
        RemoteEvent(type: .mouseMove, point: point, keyCode: nil, deltaX: nil, deltaY: nil)
    }

    public static func mouseClick(type: RemoteEventType, at point: CGPoint) -> RemoteEvent {
        RemoteEvent(type: type, point: point, keyCode: nil, deltaX: nil, deltaY: nil)
    }

    public static func key(type: RemoteEventType, code: CGKeyCode) -> RemoteEvent {
        RemoteEvent(type: type, point: nil, keyCode: code, deltaX: nil, deltaY: nil)
    }
}

// MARK: - Local Event Snapshot

public struct EventSnapshot: Sendable {
    public let location: CGPoint
    public let type: CGEventType
    public let keyCode: Int64
    public let scrollDeltaY: Int64
    public let scrollDeltaX: Int64
    public let mouseDeltaX: Int64
    public let mouseDeltaY: Int64
    public let flags: CGEventFlags

    public init(from event: CGEvent, type: CGEventType) {
        self.location = event.location
        self.type = type
        self.keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        self.scrollDeltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        self.scrollDeltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        self.mouseDeltaX = event.getIntegerValueField(.mouseEventDeltaX)
        self.mouseDeltaY = event.getIntegerValueField(.mouseEventDeltaY)
        self.flags = event.flags
    }

    public init(
        location: CGPoint,
        type: CGEventType,
        keyCode: Int64,
        scrollDeltaY: Int64,
        scrollDeltaX: Int64,
        mouseDeltaX: Int64,
        mouseDeltaY: Int64,
        flags: CGEventFlags
    ) {
        self.location = location
        self.type = type
        self.keyCode = keyCode
        self.scrollDeltaY = scrollDeltaY
        self.scrollDeltaX = scrollDeltaX
        self.mouseDeltaX = mouseDeltaX
        self.mouseDeltaY = mouseDeltaY
        self.flags = flags
    }

    public func withLocation(_ newLocation: CGPoint) -> EventSnapshot {
        EventSnapshot(
            location: newLocation,
            type: self.type,
            keyCode: self.keyCode,
            scrollDeltaY: self.scrollDeltaY,
            scrollDeltaX: self.scrollDeltaX,
            mouseDeltaX: self.mouseDeltaX,
            mouseDeltaY: self.mouseDeltaY,
            flags: self.flags)
    }
}
