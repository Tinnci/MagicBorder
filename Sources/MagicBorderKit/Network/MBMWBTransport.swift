import AppKit
import Foundation
import Network

@MainActor
public final class MBMWBTransport: MBTransport {
    public var events: AsyncStream<MBTransportEvent>

    private let service: MWBCompatibilityService
    private let localName: String
    private var settings: MBCompatibilitySettings
    private var continuation: AsyncStream<MBTransportEvent>.Continuation?
    private var serviceEventsTask: Task<Void, Never>?
    private var peerIDs: [Int32: UUID] = [:]
    private var lastMouseLocation: CGPoint?
    private var mouseCoalescer: MouseCoalescer?

    public init(
        localName: String,
        localID: Int32,
        settings: MBCompatibilitySettings)
    {
        self.localName = localName
        self.settings = settings
        self.service = MWBCompatibilityService(
            localName: localName,
            localId: localID,
            messagePort: settings.messagePort,
            clipboardPort: settings.clipboardPort)

        var continuation: AsyncStream<MBTransportEvent>.Continuation?
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation
        self.mouseCoalescer = MouseCoalescer(transport: self)
        self.serviceEventsTask = Task { @MainActor [weak self] in
            await self?.consumeServiceEvents()
        }
    }

    deinit {
        self.serviceEventsTask?.cancel()
        self.continuation?.finish()
    }

    public func start() {}

    public func stop() {
        self.service.stop()
    }

    public func updateConfiguration(securityKey: String, settings: MBCompatibilitySettings) {
        self.settings = settings
        self.service.updatePorts(
            messagePort: settings.messagePort,
            clipboardPort: settings.clipboardPort)

        let trimmed = securityKey.replacingOccurrences(of: " ", with: "")
        guard trimmed.count >= 16 else {
            self.service.stop()
            self.continuation?.yield(.log("Compatibility mode stopped: security key invalid"))
            return
        }

        self.service.updateSecurityKey(securityKey)
        self.service.start(securityKey: securityKey)
    }

    public func connect(to endpoint: NWEndpoint) {
        if case .hostPort(let host, let port) = endpoint {
            self.connectToHost(ip: Self.hostString(host), port: port.rawValue)
        }
    }

    public func connect(to result: NWBrowser.Result) {
        self.connect(to: result.endpoint)
    }

    public func connectToHost(ip: String, port: UInt16) {
        self.service.connectToHost(
            ip: ip,
            messagePort: port,
            clipboardPort: self.settings.clipboardPort)
    }

    static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .name(let name, _):
            return name
        case .ipv4(let address):
            return "\(address)"
        case .ipv6(let address):
            return "\(address)"
        @unknown default:
            return "\(host)"
        }
    }

    public func disconnect(machine _: Machine) {}

    public func reconnect(machine _: Machine) {}

    public func activate(machine: Machine?) {
        self.service.sendNextMachine(targetId: machine?.mwbPeerID)
        if machine == nil {
            self.service.stopAutoReconnect()
        }
    }

    public func centerRemoteCursor() {
        self.service.sendMouseEvent(x: 32767, y: 32767, wheel: 0, flags: 0x200)
    }

    public func sendRemoteInput(snapshot: EventSnapshot, activeMachineId _: UUID?) {
        switch snapshot.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            self.mouseCoalescer?.update(snapshot: snapshot)
        default:
            self.mouseCoalescer?.forceFlush(snapshot: snapshot)
        }
    }

    public func sendClipboardText(_ text: String, activeMachineId _: UUID?) {
        self.service.sendClipboardText(text)
    }

    public func sendClipboardImage(_ data: Data, activeMachineId _: UUID?) {
        self.service.sendClipboardImage(data)
    }

    public func sendScreenCapture(_ data: Data, to peerID: Int32?) {
        self.service.sendClipboardImage(data, to: peerID)
    }

    public func sendMachineMatrix(names: [String], twoRow: Bool, swap: Bool) {
        self.service.sendMachineMatrix(names.map { $0.uppercased() }, twoRow: twoRow, swap: swap)
    }

    public func sendFileDrop(_ urls: [URL]) {
        self.service.sendFileDrop(urls)
    }

    fileprivate func sendCompatibilityInputInternal(snapshot: EventSnapshot) {
        guard let screen = NSScreen.main else { return }
        let bounds = screen.frame
        let location = snapshot.location

        let normalizedX = Int32(((location.x - bounds.minX) / bounds.width) * 65535.0)
        let normalizedY = Int32(((location.y - bounds.minY) / bounds.height) * 65535.0)

        switch snapshot.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            if self.settings.moveMouseRelatively, let last = self.lastMouseLocation {
                let dx = Int32(location.x - last.x)
                let dy = Int32(location.y - last.y)
                let offset: Int32 = 100000
                let relX = dx + (dx < 0 ? -offset : offset)
                let winDy = -dy
                let relY = winDy + (winDy < 0 ? -offset : offset)
                self.service.sendMouseEvent(x: relX, y: relY, wheel: 0, flags: 0x200)
            } else {
                self.service.sendMouseEvent(x: normalizedX, y: normalizedY, wheel: 0, flags: 0x200)
            }
            self.lastMouseLocation = location
        case .leftMouseDown:
            self.service.sendMouseEvent(x: normalizedX, y: normalizedY, wheel: 0, flags: 0x201)
        case .leftMouseUp:
            self.service.sendMouseEvent(x: normalizedX, y: normalizedY, wheel: 0, flags: 0x202)
        case .rightMouseDown:
            self.service.sendMouseEvent(x: normalizedX, y: normalizedY, wheel: 0, flags: 0x204)
        case .rightMouseUp:
            self.service.sendMouseEvent(x: normalizedX, y: normalizedY, wheel: 0, flags: 0x205)
        case .scrollWheel:
            self.service.sendMouseEvent(
                x: normalizedX,
                y: normalizedY,
                wheel: Int32(snapshot.scrollDeltaY),
                flags: 0x20A)
        case .keyDown:
            if let key = MBInputManager.shared.windowsKeyCode(for: CGKeyCode(snapshot.keyCode)) {
                self.service.sendKeyEvent(keyCode: key, flags: 0)
            }
        case .keyUp:
            if let key = MBInputManager.shared.windowsKeyCode(for: CGKeyCode(snapshot.keyCode)) {
                self.service.sendKeyEvent(keyCode: key, flags: 0x80)
            }
        case .flagsChanged:
            let macKey = CGKeyCode(snapshot.keyCode)
            guard let key = MBInputManager.shared.windowsKeyCode(for: macKey) else { return }
            let isDown: Bool = switch macKey {
            case 56, 60:
                snapshot.flags.contains(.maskShift)
            case 59, 62:
                snapshot.flags.contains(.maskControl)
            case 58, 61:
                snapshot.flags.contains(.maskAlternate)
            case 55, 54:
                snapshot.flags.contains(.maskCommand)
            case 57:
                snapshot.flags.contains(.maskAlphaShift)
            default:
                snapshot.flags.contains(.maskNonCoalesced)
            }
            self.service.sendKeyEvent(keyCode: key, flags: isDown ? 0 : 0x80)
        default:
            break
        }
    }

    private func consumeServiceEvents() async {
        for await event in self.service.events {
            switch event {
            case .connected(let peer):
                let id = self.uuid(for: peer.id)
                self.continuation?.yield(.machineConnected(Machine(id: id, name: peer.name, state: .connected, mwbPeerID: peer.id)))
            case .disconnected(let peer):
                guard let id = self.peerIDs[peer.id] else { continue }
                self.continuation?.yield(.machineDisconnected(id))
            case .remoteMouse(let event):
                self.continuation?.yield(.mwbMouse(event))
            case .remoteKey(let event):
                self.continuation?.yield(.mwbKey(event))
            case .machineSwitched(let peer):
                let id = peer.map { self.uuid(for: $0.id) }
                self.continuation?.yield(.activeMachineChanged(id, peer?.name))
            case .machineMatrix(let matrix):
                self.continuation?.yield(.arrangementReceived(matrix))
            case .matrixOptionsUpdated(let twoRow, let swap):
                self.continuation?.yield(.arrangementOptionsUpdated(twoRow: twoRow, swap: swap))
            case .clipboardText(let text):
                self.continuation?.yield(.clipboardText(text))
            case .clipboardImage(let data):
                self.continuation?.yield(.clipboardImage(data))
            case .clipboardFiles(let urls):
                self.continuation?.yield(.clipboardFiles(urls))
            case .hideMouse:
                self.continuation?.yield(.hideMouse)
            case .dragDropOperation(let sourceName):
                self.continuation?.yield(.dragDropStateChanged(.dropping, sourceName: sourceName))
            case .dragDropBegin(let sourceName):
                self.continuation?.yield(.dragDropStateChanged(.dragging, sourceName: sourceName))
            case .dragDropEnd:
                self.continuation?.yield(.dragDropStateChanged(nil, sourceName: nil))
            case .captureScreen(let sourceId):
                self.continuation?.yield(.screenCaptureRequested(sourceId))
            case .reconnectAttempt(let host):
                self.continuation?.yield(.reconnectAttempt(host))
            case .reconnectStopped(let host):
                self.continuation?.yield(.reconnectStopped(host))
            case .log(let message):
                self.continuation?.yield(.log(message))
            case .error(let message):
                self.continuation?.yield(.error(message))
            }
        }
    }

    private func uuid(for peerID: Int32) -> UUID {
        if let existing = self.peerIDs[peerID] {
            return existing
        }
        let id = UUID()
        self.peerIDs[peerID] = id
        return id
    }
}

private final class MouseCoalescer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.magicborder.mwb.mouse.coalescing", qos: .userInteractive)
    private weak var transport: MBMWBTransport?
    private var pendingSnapshot: EventSnapshot?
    private var lastSendTime: CFAbsoluteTime = 0
    private let minInterval: TimeInterval = 0.008

    init(transport: MBMWBTransport) {
        self.transport = transport
    }

    func update(snapshot: EventSnapshot) {
        self.queue.async {
            self.pendingSnapshot = snapshot
            self.tryFlush()
        }
    }

    func forceFlush(snapshot: EventSnapshot) {
        self.queue.sync {
            self.pendingSnapshot = nil
            self.lastSendTime = CFAbsoluteTimeGetCurrent()
            Task { @MainActor [weak self] in
                self?.transport?.sendCompatibilityInputInternal(snapshot: snapshot)
            }
        }
    }

    private func tryFlush() {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - self.lastSendTime
        if elapsed >= self.minInterval, let snapshot = self.pendingSnapshot {
            self.pendingSnapshot = nil
            self.lastSendTime = now
            Task { @MainActor [weak self] in
                self?.transport?.sendCompatibilityInputInternal(snapshot: snapshot)
            }
        } else if let snapshot = self.pendingSnapshot {
            let delay = max(0, self.minInterval - elapsed)
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.pendingSnapshot?.location == snapshot.location else { return }
                self.tryFlush()
            }
        }
    }
}
