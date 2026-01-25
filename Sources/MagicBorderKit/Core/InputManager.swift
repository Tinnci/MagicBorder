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
