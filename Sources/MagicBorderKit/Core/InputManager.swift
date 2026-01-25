@preconcurrency import Cocoa
import CoreGraphics
import Observation

@MainActor
@Observable
public class MBInputManager: Observation.Observable {
    public static let shared = MBInputManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public var isIntercepting: Bool = false

    public func toggleInterception(_ enable: Bool) {
        if enable {
            startTap()
        } else {
            stopTap()
        }
    }

    private func startTap() {
        guard eventTap == nil else { return }

        let eventMask =
            (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue) | (1 << CGEventType.scrollWheel.rawValue)
            | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        // Context to pass 'self' to the C callback
        let observer = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: globalEventTapCallback,
                userInfo: observer
            )
        else {
            print("Failed to create event tap. Check accessibility permissions.")
            return
        }

        self.eventTap = tap

        // Create a run loop source and add it to the current run loop
        // Use nil for kCFAllocatorDefault
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.isIntercepting = true
        print("Input interception started.")
    }

    private func stopTap() {
        guard let tap = eventTap, let source = runLoopSource else { return }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)

        self.eventTap = nil
        self.runLoopSource = nil

        self.isIntercepting = false
        print("Input interception stopped.")
    }

    nonisolated func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<
        CGEvent
    >? {
        // Core Logic
        // Since this is nonisolated, we cannot access MainActor state directly without a Task or assumeIsolated.
        // However, for high-performance event filtering, we want to stay synchronous.

        // For now, pass-through
        return Unmanaged.passRetained(event)
    }

    // MARK: - Remote Event Simulation (MWB Compatibility)

    public func simulateMouseEvent(_ event: MWBMouseEvent) {
        guard let screen = NSScreen.main else { return }
        let width = screen.frame.width
        let height = screen.frame.height

        let x = CGFloat(event.x) * width / 65535.0
        let y = CGFloat(event.y) * height / 65535.0
        let location = CGPoint(x: x, y: height - y)

        let type: CGEventType
        let flags = event.flags

        switch flags {
        case 0x200: // WM_MOUSEMOVE
            type = .mouseMoved
        case 0x201: // WM_LBUTTONDOWN
            type = .leftMouseDown
        case 0x202: // WM_LBUTTONUP
            type = .leftMouseUp
        case 0x204: // WM_RBUTTONDOWN
            type = .rightMouseDown
        case 0x205: // WM_RBUTTONUP
            type = .rightMouseUp
        case 0x20A: // WM_MOUSEWHEEL
            type = .scrollWheel
        default:
            type = .mouseMoved
        }

        if type == .scrollWheel {
            let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(event.wheel), wheel2: 0, wheel3: 0)
            scroll?.post(tap: .cghidEventTap)
            return
        }

        if let cgEvent = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left) {
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    public func simulateKeyEvent(_ event: MWBKeyEvent) {
        guard let keyCode = Self.keyCodeMap[Int(event.keyCode)] else { return }
        let isKeyUp = (event.flags & 0x80) != 0 // LLKHF.UP

        if let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: !isKeyUp) {
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    private static let keyCodeMap: [Int: CGKeyCode] = [
        0x41: 0,   // A
        0x53: 1,   // S
        0x44: 2,   // D
        0x46: 3,   // F
        0x48: 4,   // H
        0x47: 5,   // G
        0x5A: 6,   // Z
        0x58: 7,   // X
        0x43: 8,   // C
        0x56: 9,   // V
        0x42: 11,  // B
        0x51: 12,  // Q
        0x57: 13,  // W
        0x45: 14,  // E
        0x52: 15,  // R
        0x59: 16,  // Y
        0x54: 17,  // T
        0x31: 18,  // 1
        0x32: 19,  // 2
        0x33: 20,  // 3
        0x34: 21,  // 4
        0x36: 22,  // 6
        0x35: 23,  // 5
        0x39: 25,  // 9
        0x37: 26,  // 7
        0x38: 28,  // 8
        0x30: 29,  // 0
        0x4F: 31,  // O
        0x55: 32,  // U
        0x49: 34,  // I
        0x50: 35,  // P
        0x0D: 36,  // Enter
        0x4C: 37,  // L
        0x4A: 38,  // J
        0x4B: 40,  // K
        0xBA: 41,  // ;
        0xDE: 39,  // '
        0xDB: 33,  // [
        0xDD: 30,  // ]
        0xDC: 42,  // \
        0xBC: 43,  // ,
        0xBE: 47,  // .
        0xBF: 44,  // /
        0x20: 49,  // Space
        0x1B: 53,  // Esc
        0x08: 51,  // Backspace
        0x09: 48,  // Tab
        0x14: 57   // Caps Lock
    ]
}

// Global callback function matching CGEventTapCallBack signature
func globalEventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passRetained(event)
    }

    let manager = Unmanaged<MBInputManager>.fromOpaque(refcon).takeUnretainedValue()
    // Directly call nonisolated handle method
    return manager.handle(proxy: proxy, type: type, event: event)
}
