@preconcurrency import AppKit
import CoreGraphics
public import Foundation
private import OSLog
public import Observation
private import os

/// Coordinates local HID event interception (`CGEventTap`), clipboard polling delegation,
/// and incoming remote input simulation.
@MainActor
@Observable
public final class MBInputManager: Observation.Observable {
    private struct TapState: Sendable {
        var remoteID: UUID?
        var isAppActive: Bool
        var lastLocalInteraction: TimeInterval = 0
        var wrapCursor: Bool = true
        var mainScreenFrame: CGRect?
        var virtualCursor = MBVirtualCursorTracker()
    }

    private enum TapAction {
        case passThrough
        case reenableTap
        case forceEscape
        case forwardLocalMouse(EventSnapshot)
        case forwardRemote(EventSnapshot, isMouseMove: Bool)
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var clipboardMonitor: MBPasteboardMonitor?
    private let appLifecycleTask = CancellableTaskSlot()

    private let pasteboard: any PasteboardAccessing
    private let synthesizer: any MBInputEventSynthesizing
    private let screenGeometry: any ScreenGeometryProviding
    private let tapState: OSAllocatedUnfairLock<TapState>

    public var isIntercepting: Bool = false

    public var currentRemoteID: UUID? {
        self.tapState.withLock { $0.remoteID }
    }

    /// Injected by `MBNetworkManager` during startup to break the circular dependency.
    public weak var routingDelegate: (any MBInputRoutingDelegate)?

    public init(
        pasteboard: any PasteboardAccessing = SystemPasteboard(),
        synthesizer: any MBInputEventSynthesizing = MBCGEventSynthesizer(),
        screenGeometry: any ScreenGeometryProviding = SystemScreenGeometryProvider(),
        startClipboardSync: Bool = true,
        observeAppLifecycle: Bool = true
    ) {
        self.pasteboard = pasteboard
        self.synthesizer = synthesizer
        self.screenGeometry = screenGeometry
        self.tapState = OSAllocatedUnfairLock(
            initialState: TapState(
                isAppActive: NSRunningApplication.current.isActive,
                mainScreenFrame: screenGeometry.mainScreenFrame))

        if observeAppLifecycle {
            self.startAppStateObservers()
        }
        if startClipboardSync {
            self.startClipboardSync()
        }
    }

    deinit {
        self.appLifecycleTask.cancel()
    }

    public func syncTapConfiguration(wrapCursor: Bool) {
        let frame = self.screenGeometry.mainScreenFrame
        self.tapState.withLock { state in
            state.wrapCursor = wrapCursor
            state.mainScreenFrame = frame
        }
    }

    public func startClipboardSync() {
        guard self.clipboardMonitor == nil else { return }
        let monitor = MBPasteboardMonitor(pasteboard: self.pasteboard)
        monitor.onChange = { [weak self] content in
            self?.routingDelegate?.handleLocalPasteboard(content)
        }
        self.clipboardMonitor = monitor
        monitor.startPolling()
        MBLogger.input.info("Clipboard sync started.")
    }

    public func stopClipboardSync() {
        self.clipboardMonitor?.stopPolling()
        self.clipboardMonitor = nil
        MBLogger.input.info("Clipboard sync stopped.")
    }

    public func ignoreNextClipboardChange() {
        self.clipboardMonitor?.ignoreNextChange()
    }

    public func toggleInterception(_ enable: Bool) {
        if enable {
            self.startTap()
        } else {
            self.stopTap()
        }
    }

    public func setRemoteTarget(_ id: UUID?) {
        let frame = self.screenGeometry.mainScreenFrame
        self.tapState.withLock { state in
            state.remoteID = id
            state.mainScreenFrame = frame
            if id == nil {
                state.virtualCursor.reset()
            }
        }
        MBLogger.input.info("Set remote target to: \(String(describing: id))")
    }

    public func simulateRemoteEvent(_ event: RemoteEvent) {
        self.synthesizer.simulateRemoteEvent(event)
    }

    public func simulateMouseEvent(_ event: MWBMouseEvent) {
        self.synthesizer.simulateMouseEvent(event)
    }

    public func simulateKeyEvent(_ event: MWBKeyEvent) {
        self.synthesizer.simulateKeyEvent(event)
    }

    nonisolated func handle(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent)
        -> Unmanaged<CGEvent>?
    {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return self.handleTapDisabled(event: event)
        }

        let snapshot = EventSnapshot(from: event, type: type)
        let action = self.evaluateTapAction(type: type, snapshot: snapshot)

        switch action {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .reenableTap:
            return Unmanaged.passUnretained(event)
        case .forceEscape:
            Task { @MainActor [weak self] in
                self?.routingDelegate?.forceReturnToLocal(reason: "escape")
            }
            return nil
        case .forwardLocalMouse(let localSnapshot):
            Task { @MainActor [weak self] in
                self?.routingDelegate?.handleLocalMouseEvent(snapshot: localSnapshot)
            }
            return Unmanaged.passUnretained(event)
        case .forwardRemote(let remoteSnapshot, let isMouseMove):
            Task { @MainActor [weak self] in
                guard let self, let delegate = self.routingDelegate else { return }
                if isMouseMove {
                    delegate.handleRemoteMouseEvent(snapshot: remoteSnapshot)
                }
                delegate.sendRemoteInput(snapshot: remoteSnapshot)
            }
            return nil
        }
    }

    private nonisolated func handleTapDisabled(event: CGEvent) -> Unmanaged<CGEvent> {
        Task { @MainActor [weak self] in
            guard let self, let tap = self.eventTap else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
            MBLogger.input.warning("Re-enabled CGEventTap after system disable.")
        }
        return Unmanaged.passUnretained(event)
    }

    private nonisolated func evaluateTapAction(type: CGEventType, snapshot: EventSnapshot) -> TapAction {
        let (action, warpTarget): (TapAction, CGPoint?) = self.tapState.withLock { state in
            if state.remoteID == nil {
                state.virtualCursor.reset()
                if Self.shouldAllowLocalInteraction(type: type, state: &state) {
                    return (.passThrough, nil)
                }
                if Self.isMouseMotion(type) {
                    return (.forwardLocalMouse(snapshot), nil)
                }
                return (.passThrough, nil)
            }

            if type == .keyDown, snapshot.keyCode == 53 {
                return (.forceEscape, nil)
            }

            let isMotion = Self.isMouseMotion(type)
            var updatedSnapshot = snapshot
            var nextWarpTarget: CGPoint?
            if isMotion {
                let virtualLocation = state.virtualCursor.advance(
                    startLocation: snapshot.location,
                    deltaX: snapshot.mouseDeltaX,
                    deltaY: snapshot.mouseDeltaY,
                    screenFrame: state.mainScreenFrame)
                updatedSnapshot = snapshot.withLocation(virtualLocation)
                if state.wrapCursor, let frame = state.mainScreenFrame {
                    nextWarpTarget = CGPoint(x: frame.midX, y: frame.midY)
                }
            }
            return (.forwardRemote(updatedSnapshot, isMouseMove: isMotion), nextWarpTarget)
        }

        if let warpTarget {
            CGWarpMouseCursorPosition(warpTarget)
        }
        return action
    }

    private nonisolated static func isMouseMotion(_ type: CGEventType) -> Bool {
        type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged
            || type == .otherMouseDragged
    }

    private nonisolated static func shouldAllowLocalInteraction(
        type: CGEventType,
        state: inout TapState
    ) -> Bool {
        if state.isAppActive {
            return true
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            state.lastLocalInteraction = CFAbsoluteTimeGetCurrent()
            return true
        case .keyDown, .keyUp, .flagsChanged:
            return CFAbsoluteTimeGetCurrent() - state.lastLocalInteraction < 2.0
        default:
            return false
        }
    }

    private func startTap() {
        guard self.eventTap == nil else { return }

        let eventsOfInterest: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel, .keyDown, .keyUp, .flagsChanged,
        ]
        let mask = eventsOfInterest.reduce(CGEventMask(0)) { partial, eventType in
            partial | (CGEventMask(1) << eventType.rawValue)
        }

        let observer = Unmanaged.passUnretained(self).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: globalEventTapCallback,
                userInfo: observer)
        else {
            MBLogger.input.error("Failed to create event tap. Check accessibility permissions.")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.isIntercepting = true
        MBLogger.input.info("Input interception started.")
    }

    private func stopTap() {
        guard let tap = self.eventTap, let source = self.runLoopSource else { return }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)

        self.eventTap = nil
        self.runLoopSource = nil
        self.isIntercepting = false
        MBLogger.input.info("Input interception stopped.")
    }

    private func startAppStateObservers() {
        let tapState = self.tapState
        let becameActiveName = NSApplication.didBecomeActiveNotification
        let resignedActiveName = NSApplication.didResignActiveNotification
        let task = Task.detached {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await Self.observeNotification(
                        name: becameActiveName,
                        isActive: true,
                        tapState: tapState)
                }
                group.addTask {
                    await Self.observeNotification(
                        name: resignedActiveName,
                        isActive: false,
                        tapState: tapState)
                }
            }
        }
        self.appLifecycleTask.replace(with: task)
    }

    private nonisolated static func observeNotification(
        name: Notification.Name,
        isActive: Bool,
        tapState: OSAllocatedUnfairLock<TapState>
    ) async {
        for await _ in NotificationCenter.default.notifications(named: name) {
            guard !Task.isCancelled else { break }
            tapState.withLock { $0.isAppActive = isActive }
        }
    }
}

private func globalEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<MBInputManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handle(proxy: proxy, type: type, event: event)
}
