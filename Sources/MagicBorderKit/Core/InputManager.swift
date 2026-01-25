@preconcurrency import Cocoa
import CoreGraphics
import OSLog
import Observation
import os

@MainActor
@Observable
public class MBInputManager: Observation.Observable {
    public static let shared = MBInputManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public var isIntercepting: Bool = false

    // Thread-safe storage for the current remote machine ID
    // Accessed by both MainActor and the non-isolated C callback
    private let _remoteID = OSAllocatedUnfairLock<UUID?>(initialState: nil)
    private let _isAppActive = OSAllocatedUnfairLock<Bool>(initialState: true)

    public var currentRemoteID: UUID? {
        _remoteID.withLock { $0 }
    }

    public init() {
        _isAppActive.withLock { $0 = NSRunningApplication.current.isActive }
        setupAppStateObservers()
    }

    public func toggleInterception(_ enable: Bool) {
        if enable {
            startTap()
        } else {
            stopTap()
        }
    }

    public func setRemoteTarget(_ id: UUID?) {
        _remoteID.withLock { $0 = id }
        MBLogger.input.info("Set remote target to: \(String(describing: id))")
    }

    private func startTap() {
        guard eventTap == nil else { return }

        var mask: UInt64 = 0
        mask |= (1 << CGEventType.mouseMoved.rawValue)
        mask |= (1 << CGEventType.leftMouseDown.rawValue)
        mask |= (1 << CGEventType.leftMouseUp.rawValue)
        mask |= (1 << CGEventType.leftMouseDragged.rawValue)
        mask |= (1 << CGEventType.rightMouseDragged.rawValue)
        mask |= (1 << CGEventType.rightMouseDown.rawValue)
        mask |= (1 << CGEventType.rightMouseUp.rawValue)
        mask |= (1 << CGEventType.scrollWheel.rawValue)
        mask |= (1 << CGEventType.keyDown.rawValue)
        mask |= (1 << CGEventType.keyUp.rawValue)
        mask |= (1 << CGEventType.flagsChanged.rawValue)

        // Context to pass 'self' to the C callback
        let observer = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: globalEventTapCallback,
                userInfo: observer
            )
        else {
            MBLogger.input.error("Failed to create event tap. Check accessibility permissions.")
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
        MBLogger.input.info("Input interception started.")
    }

    private func stopTap() {
        guard let tap = eventTap, let source = runLoopSource else { return }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)

        self.eventTap = nil
        self.runLoopSource = nil

        self.isIntercepting = false
        MBLogger.input.info("Input interception stopped.")
    }

    nonisolated func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<
        CGEvent
    >? {
        if shouldAllowLocalInteraction(type: type) {
            return Unmanaged.passUnretained(event)
        }

        // Create snapshot synchronously (safe)
        let snapshot = EventSnapshot(from: event, type: type)

        // Core Logic
        guard _remoteID.withLock({ $0 }) != nil else {
            if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged {
                Task { @MainActor in
                    MBNetworkManager.shared.handleLocalMouseEvent(snapshot: snapshot)
                }
            }
            // Local mode: pass-through
            return Unmanaged.passUnretained(event)
        }

        // Remote mode: intercept and send
        guard convertToRemoteEvent(snapshot: snapshot) != nil else {
            // If we can't convert it (e.g. some system event), maybe let it pass or just consume?
            // Safest is to consume if we are "in remote mode" to avoid local ghost clicks.
            return nil
        }

        Task { @MainActor in
            MBNetworkManager.shared.sendRemoteInput(snapshot: snapshot)
        }

        return nil
    }

    private nonisolated func shouldAllowLocalInteraction(type: CGEventType) -> Bool {
        if _isAppActive.withLock({ $0 }) {
            return true
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp:
            return true
        default:
            return false
        }
    }

    private func setupAppStateObservers() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?._isAppActive.withLock { $0 = true }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?._isAppActive.withLock { $0 = false }
        }
    }

    nonisolated func convertToRemoteEvent(_ event: CGEvent, type: CGEventType)
        -> RemoteEvent?
    {
        let snapshot = EventSnapshot(from: event, type: type)
        return convertToRemoteEvent(snapshot: snapshot)
    }

    nonisolated func convertToRemoteEvent(snapshot: EventSnapshot) -> RemoteEvent? {
        switch snapshot.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            return RemoteEvent.mouseMove(at: snapshot.location)
        case .leftMouseDown:
            return RemoteEvent.mouseClick(type: .leftMouseDown, at: snapshot.location)
        case .leftMouseUp:
            return RemoteEvent.mouseClick(type: .leftMouseUp, at: snapshot.location)
        case .rightMouseDown:
            return RemoteEvent.mouseClick(type: .rightMouseDown, at: snapshot.location)
        case .rightMouseUp:
            return RemoteEvent.mouseClick(type: .rightMouseUp, at: snapshot.location)
        case .scrollWheel:
            return RemoteEvent(
                type: .scrollWheel, point: nil, keyCode: nil, deltaX: Int(snapshot.scrollDeltaX),
                deltaY: Int(snapshot.scrollDeltaY))
        case .keyDown:
            let code = CGKeyCode(snapshot.keyCode)
            return RemoteEvent.key(type: .keyDown, code: code)
        case .keyUp:
            let code = CGKeyCode(snapshot.keyCode)
            return RemoteEvent.key(type: .keyUp, code: code)
        default:
            return nil
        }
    }

    // MARK: - Native Remote Event Simulation

    public func simulateRemoteEvent(_ event: RemoteEvent) {
        switch event.type {
        case .mouseMove:
            if let point = event.point {
                let cgEvent = CGEvent(
                    mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
                    mouseButton: .left)
                cgEvent?.post(tap: .cghidEventTap)
            }
        case .leftMouseDown:
            if let point = event.point {
                let cgEvent = CGEvent(
                    mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point,
                    mouseButton: .left)
                cgEvent?.post(tap: .cghidEventTap)
            }
        case .leftMouseUp:
            if let point = event.point {
                let cgEvent = CGEvent(
                    mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point,
                    mouseButton: .left)
                cgEvent?.post(tap: .cghidEventTap)
            }
        case .rightMouseDown:
            if let point = event.point {
                let cgEvent = CGEvent(
                    mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point,
                    mouseButton: .right)
                cgEvent?.post(tap: .cghidEventTap)
            }
        case .rightMouseUp:
            if let point = event.point {
                let cgEvent = CGEvent(
                    mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point,
                    mouseButton: .right)
                cgEvent?.post(tap: .cghidEventTap)
            }
        case .scrollWheel:
            // DeltaX/Y would be needed in RemoteEvent.
            // Protocol.swift says: let deltaX: Int?, let deltaY: Int?
            let wheel1 = Int32(event.deltaY ?? 0)
            let wheel2 = Int32(event.deltaX ?? 0)
            let scroll = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: wheel1,
                wheel2: wheel2, wheel3: 0)
            scroll?.post(tap: .cghidEventTap)

        case .keyDown:
            if let code = event.keyCode {
                let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
                cgEvent?.post(tap: .cghidEventTap)
            }
        case .keyUp:
            if let code = event.keyCode {
                let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
                cgEvent?.post(tap: .cghidEventTap)
            }
        }
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
        case 0x200:  // WM_MOUSEMOVE
            type = .mouseMoved
        case 0x201:  // WM_LBUTTONDOWN
            type = .leftMouseDown
        case 0x202:  // WM_LBUTTONUP
            type = .leftMouseUp
        case 0x204:  // WM_RBUTTONDOWN
            type = .rightMouseDown
        case 0x205:  // WM_RBUTTONUP
            type = .rightMouseUp
        case 0x20A:  // WM_MOUSEWHEEL
            type = .scrollWheel
        default:
            type = .mouseMoved
        }

        if type == .scrollWheel {
            let scroll = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                wheel1: Int32(event.wheel), wheel2: 0, wheel3: 0)
            scroll?.post(tap: .cghidEventTap)
            return
        }

        if let cgEvent = CGEvent(
            mouseEventSource: nil, mouseType: type, mouseCursorPosition: location,
            mouseButton: .left)
        {
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    public func simulateKeyEvent(_ event: MWBKeyEvent) {
        guard let keyCode = Self.keyCodeMap[Int(event.keyCode)] else { return }
        let isKeyUp = (event.flags & 0x80) != 0  // LLKHF.UP

        if let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: !isKeyUp) {
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    private static let keyCodeMap: [Int: CGKeyCode] = [
        // Letters
        0x41: 0,  // A
        0x42: 11,  // B
        0x43: 8,  // C
        0x44: 2,  // D
        0x45: 14,  // E
        0x46: 3,  // F
        0x47: 5,  // G
        0x48: 4,  // H
        0x49: 34,  // I
        0x4A: 38,  // J
        0x4B: 40,  // K
        0x4C: 37,  // L
        0x4D: 46,  // M
        0x4E: 45,  // N
        0x4F: 31,  // O
        0x50: 35,  // P
        0x51: 12,  // Q
        0x52: 15,  // R
        0x53: 1,  // S
        0x54: 17,  // T
        0x55: 32,  // U
        0x56: 9,  // V
        0x57: 13,  // W
        0x58: 7,  // X
        0x59: 16,  // Y
        0x5A: 6,  // Z

        // Numbers
        0x30: 29,  // 0
        0x31: 18,  // 1
        0x32: 19,  // 2
        0x33: 20,  // 3
        0x34: 21,  // 4
        0x35: 23,  // 5
        0x36: 22,  // 6
        0x37: 26,  // 7
        0x38: 28,  // 8
        0x39: 25,  // 9

        // Function Keys
        0x70: 122,  // F1
        0x71: 120,  // F2
        0x72: 99,  // F3
        0x73: 118,  // F4
        0x74: 96,  // F5
        0x75: 97,  // F6
        0x76: 98,  // F7
        0x77: 100,  // F8
        0x78: 101,  // F9
        0x79: 109,  // F10
        0x7A: 103,  // F11
        0x7B: 111,  // F12

        // Special Keys
        0x0D: 36,  // Enter
        0x20: 49,  // Space
        0x1B: 53,  // Esc
        0x08: 51,  // Backspace
        0x09: 48,  // Tab
        0x14: 57,  // Caps Lock
        0x10: 56,  // Shift (Left) - Windows VK maps generalized usually
        0x11: 59,  // Ctrl (Left)
        0x12: 58,  // Alt (Left) / Option
        0x5B: 55,  // Windows Key (Left) / Command
        0x5C: 54,  // Windows Key (Right) / Command

        // Punctuation
        0xBA: 41,  // ;
        0xDE: 39,  // '
        0xDB: 33,  // [
        0xDD: 30,  // ]
        0xDC: 42,  // \
        0xBC: 43,  // ,
        0xBE: 47,  // .
        0xBF: 44,  // /
        0xC0: 50,  // `
        0xBD: 27,  // -
        0xBB: 24,  // =

        // Navigation
        0x25: 123,  // Left Arrow
        0x26: 126,  // Up Arrow
        0x27: 124,  // Right Arrow
        0x28: 125,  // Down Arrow
        0x21: 116,  // Page Up
        0x22: 121,  // Page Down
        0x24: 115,  // Home
        0x23: 119,  // End
        0x2D: 114,  // Insert
        0x2E: 117,  // Delete
    ]

    private static let windowsKeyCodeMap: [CGKeyCode: Int32] = {
        var map: [CGKeyCode: Int32] = [:]
        for (win, mac) in keyCodeMap {
            map[mac] = Int32(win)
        }
        return map
    }()

    public func windowsKeyCode(for macKeyCode: CGKeyCode) -> Int32? {
        Self.windowsKeyCodeMap[macKeyCode]
    }
}

// Global callback function matching CGEventTapCallBack signature
func globalEventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<MBInputManager>.fromOpaque(refcon).takeUnretainedValue()
    // Directly call nonisolated handle method
    return manager.handle(proxy: proxy, type: type, event: event)
}
