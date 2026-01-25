import Foundation
import CoreGraphics

// MARK: - Packet Types

enum PacketType: Codable {
    case handshake(info: MachineInfo)
    case inputEvent(RemoteEvent)
    case clipboardData(ClipboardPayload)
    case heartbeat
    case bye
}

// MARK: - Payloads

struct MachineInfo: Codable, Equatable {
    let id: UUID
    let name: String
    let screenWidth: Double
    let screenHeight: Double
}

struct ClipboardPayload: Codable {
    let content: Data
    let type: ClipboardType
}

enum ClipboardType: Codable {
    case text
    case image
}

// MARK: - Input Events

enum RemoteEventType: Codable {
    case mouseMove
    case leftMouseDown, leftMouseUp
    case rightMouseDown, rightMouseUp
    case scrollWheel
    case keyDown, keyUp
}

struct RemoteEvent: Codable {
    let type: RemoteEventType
    let point: CGPoint? // For mouse events
    let keyCode: CGKeyCode? // For key events
    let deltaX: Int? // For Scroll
    let deltaY: Int? // For Scroll
    
    // Helper init for Mouse Move
    static func mouseMove(at point: CGPoint) -> RemoteEvent {
        return RemoteEvent(type: .mouseMove, point: point, keyCode: nil, deltaX: nil, deltaY: nil)
    }
    
    // Helper init for Click
    static func mouseClick(type: RemoteEventType, at point: CGPoint) -> RemoteEvent {
        return RemoteEvent(type: type, point: point, keyCode: nil, deltaX: nil, deltaY: nil)
    }
    
    // Helper init for Key
    static func key(type: RemoteEventType, code: CGKeyCode) -> RemoteEvent {
        return RemoteEvent(type: type, point: nil, keyCode: code, deltaX: nil, deltaY: nil)
    }
}
