import CoreGraphics

/// Synthesizes incoming remote mouse/keyboard events onto the local macOS HID stream.
@MainActor
public protocol MBInputEventSynthesizing: AnyObject {
    func simulateRemoteEvent(_ event: RemoteEvent)
    func simulateMouseEvent(_ event: MWBMouseEvent)
    func simulateKeyEvent(_ event: MWBKeyEvent)
}

@MainActor
public final class MBCGEventSynthesizer: MBInputEventSynthesizing {
    private let screenGeometry: any ScreenGeometryProviding

    public init(screenGeometry: any ScreenGeometryProviding = SystemScreenGeometryProvider()) {
        self.screenGeometry = screenGeometry
    }

    public func simulateRemoteEvent(_ event: RemoteEvent) {
        switch event.type {
        case .mouseMove:
            if let point = event.point {
                Self.postMouseEvent(type: .mouseMoved, at: point, button: .left)
            }
        case .leftMouseDown:
            if let point = event.point {
                Self.postMouseEvent(type: .leftMouseDown, at: point, button: .left)
            }
        case .leftMouseUp:
            if let point = event.point {
                Self.postMouseEvent(type: .leftMouseUp, at: point, button: .left)
            }
        case .rightMouseDown:
            if let point = event.point {
                Self.postMouseEvent(type: .rightMouseDown, at: point, button: .right)
            }
        case .rightMouseUp:
            if let point = event.point {
                Self.postMouseEvent(type: .rightMouseUp, at: point, button: .right)
            }
        case .scrollWheel:
            Self.postScrollEvent(wheelY: Int32(event.deltaY ?? 0), wheelX: Int32(event.deltaX ?? 0))
        case .keyDown:
            if let code = event.keyCode {
                Self.postKeyEvent(virtualKey: code, keyDown: true)
            }
        case .keyUp:
            if let code = event.keyCode {
                Self.postKeyEvent(virtualKey: code, keyDown: false)
            }
        }
    }

    public func simulateMouseEvent(_ event: MWBMouseEvent) {
        guard let frame = self.screenGeometry.mainScreenFrame else { return }
        let width = frame.width
        let height = frame.height

        let x = CGFloat(event.x) * width / 65535.0
        let y = CGFloat(event.y) * height / 65535.0
        let location = CGPoint(x: x, y: height - y)

        if event.flags == 0x20A {  // WM_MOUSEWHEEL
            Self.postScrollEvent(wheelY: Int32(event.wheel), wheelX: 0)
            return
        }

        let (eventType, button) = Self.cgMouseTypeAndButton(forMWBFlags: event.flags)
        Self.postMouseEvent(type: eventType, at: location, button: button)
    }

    public func simulateKeyEvent(_ event: MWBKeyEvent) {
        guard let keyCode = MBKeyCodeMapper.macKeyCode(forWindowsKeyCode: event.keyCode) else { return }
        let isKeyUp = (event.flags & 0x80) != 0  // LLKHF.UP
        Self.postKeyEvent(virtualKey: keyCode, keyDown: !isKeyUp)
    }

    private static func cgMouseTypeAndButton(forMWBFlags flags: Int32) -> (CGEventType, CGMouseButton) {
        switch flags {
        case 0x200:  // WM_MOUSEMOVE
            (.mouseMoved, .left)
        case 0x201:  // WM_LBUTTONDOWN
            (.leftMouseDown, .left)
        case 0x202:  // WM_LBUTTONUP
            (.leftMouseUp, .left)
        case 0x204:  // WM_RBUTTONDOWN
            (.rightMouseDown, .right)
        case 0x205:  // WM_RBUTTONUP
            (.rightMouseUp, .right)
        default:
            (.mouseMoved, .left)
        }
    }

    private static func postMouseEvent(type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button)
        cgEvent?.post(tap: .cghidEventTap)
    }

    private static func postScrollEvent(wheelY: Int32, wheelX: Int32) {
        let scroll = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: wheelY,
            wheel2: wheelX,
            wheel3: 0)
        scroll?.post(tap: .cghidEventTap)
    }

    private static func postKeyEvent(virtualKey: CGKeyCode, keyDown: Bool) {
        let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: keyDown)
        cgEvent?.post(tap: .cghidEventTap)
    }
}
