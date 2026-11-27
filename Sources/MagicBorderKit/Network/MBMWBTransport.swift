import CoreGraphics
public import Foundation
public import Network

@MainActor
public final class MBMWBTransport:
    MBTransport,
    MBMatrixSyncTransport,
    MBFileDropTransport,
    MBRemoteActivationTransport
{
    public let events: AsyncStream<MBTransportEvent>

    private let service: any MWBCompatibilityServicing
    private let screenGeometry: any ScreenGeometryProviding
    private let clock: any ClockProviding
    private var settings: MBCompatibilitySettings
    private let continuation: AsyncStream<MBTransportEvent>.Continuation
    private let serviceEventsTask = CancellableTaskSlot()
    private var peerIDs: [Int32: UUID] = [:]
    private var lastMouseLocation: CGPoint?
    private var mouseCoalescer: MBMouseCoalescer?

    public init(
        localName: String,
        localID: Int32,
        settings: MBCompatibilitySettings,
        service: (any MWBCompatibilityServicing)? = nil,
        screenGeometry: any ScreenGeometryProviding = SystemScreenGeometryProvider(),
        clock: any ClockProviding = SystemClock()
    ) {
        self.settings = settings
        self.screenGeometry = screenGeometry
        self.clock = clock
        self.service =
            service
            ?? MWBCompatibilityService(
                localName: localName,
                localId: localID,
                messagePort: settings.messagePort,
                clipboardPort: settings.clipboardPort)

        let stream = AsyncStream<MBTransportEvent>.makeStream()
        self.events = stream.stream
        self.continuation = stream.continuation
        self.mouseCoalescer = MBMouseCoalescer(clock: clock) { [weak self] snapshot in
            self?.sendCompatibilityInputInternal(snapshot: snapshot)
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.consumeServiceEvents()
        }
        self.serviceEventsTask.replace(with: task)
    }

    deinit {
        self.serviceEventsTask.cancel()
        self.continuation.finish()
    }

    public func start() {}

    public func stop() {
        self.mouseCoalescer?.cancel()
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
            self.continuation.yield(.log("Compatibility mode stopped: security key invalid"))
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
            name
        case .ipv4(let address):
            "\(address)"
        case .ipv6(let address):
            "\(address)"
        @unknown default:
            "\(host)"
        }
    }

    public func disconnect(machine: Machine) {
        guard let peerID = machine.mwbPeerID else { return }
        self.service.disconnect(peerId: peerID)
    }

    public func reconnect(machine: Machine) {
        guard let peerID = machine.mwbPeerID else { return }
        self.service.reconnect(peerId: peerID)
    }

    public func activate(machine: Machine?) {
        self.releaseModifiers()
        self.service.sendNextMachine(targetId: machine?.mwbPeerID)
        if machine == nil {
            self.service.stopAutoReconnect()
        }
    }

    private func releaseModifiers() {
        for keyCode in MBKeyCodeMapper.windowsModifierKeyCodes {
            self.service.sendKeyEvent(keyCode: keyCode, flags: 0x80)
        }
    }

    public func centerRemoteCursor() {
        self.service.sendMouseEvent(x: 32767, y: 32767, wheel: 0, flags: 0x200)
    }

    public func sendRemoteInput(snapshot: EventSnapshot, activeMachineId _: UUID?) {
        switch snapshot.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
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

    private func sendCompatibilityInputInternal(snapshot: EventSnapshot) {
        guard let bounds = self.screenGeometry.mainScreenFrame,
            bounds.width > 0,
            bounds.height > 0
        else { return }

        let location = snapshot.location
        let normalizedX = Int32(((location.x - bounds.minX) / bounds.width) * 65535.0)
        let normalizedY = Int32(((location.y - bounds.minY) / bounds.height) * 65535.0)

        switch snapshot.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            self.sendMouseMotion(location: location, normalizedX: normalizedX, normalizedY: normalizedY)
        case .leftMouseDown:
            self.service.sendMouseEvent(x: normalizedX, y: normalizedY, wheel: 0, flags: 0x201)
        case .leftMouseUp:
            self.service.sendMouseEvent(x: normalizedX, y: normalizedY, wheel: 0, flags: 0x202)
        case .rightMouseDown:
            self.service.sendMouseEvent(x: normalizedX, y: normalizedY, wheel: 0, flags: 0x204)
        case .rightMouseUp:
            self.service.sendMouseEvent(x: normalizedX, y: normalizedY, wheel: 0, flags: 0x205)
        case .otherMouseDown:
            self.service.sendMouseEvent(x: normalizedX, y: normalizedY, wheel: 0, flags: 0x207)
        case .otherMouseUp:
            self.service.sendMouseEvent(x: normalizedX, y: normalizedY, wheel: 0, flags: 0x208)
        case .scrollWheel:
            let speed = max(0.25, min(3.0, self.settings.remoteScrollSpeed))
            let sign: Double = self.settings.invertRemoteScroll ? -1.0 : 1.0
            let scaledWheel = Int32((Double(snapshot.scrollDeltaY) * speed * sign).rounded())
            self.service.sendMouseEvent(
                x: normalizedX,
                y: normalizedY,
                wheel: scaledWheel == 0 && snapshot.scrollDeltaY != 0
                    ? (self.settings.invertRemoteScroll ? -1 : 1) : scaledWheel,
                flags: 0x20A)
        case .keyDown:
            if let key = MBKeyCodeMapper.windowsKeyCode(
                for: CGKeyCode(snapshot.keyCode),
                remapMode: self.settings.modifierRemapMode)
            {
                self.service.sendKeyEvent(keyCode: key, flags: 0)
            }
        case .keyUp:
            if let key = MBKeyCodeMapper.windowsKeyCode(
                for: CGKeyCode(snapshot.keyCode),
                remapMode: self.settings.modifierRemapMode)
            {
                self.service.sendKeyEvent(keyCode: key, flags: 0x80)
            }
        case .flagsChanged:
            let macKey = CGKeyCode(snapshot.keyCode)
            guard
                let key = MBKeyCodeMapper.windowsKeyCode(
                    for: macKey,
                    remapMode: self.settings.modifierRemapMode)
            else { return }
            let isDown = MBKeyCodeMapper.isModifierDown(macKeyCode: macKey, flags: snapshot.flags)
            self.service.sendKeyEvent(keyCode: key, flags: isDown ? 0 : 0x80)
        default:
            break
        }
    }

    private func sendMouseMotion(location: CGPoint, normalizedX: Int32, normalizedY: Int32) {
        if self.settings.moveMouseRelatively, let last = self.lastMouseLocation {
            let dx = Int32(location.x - last.x)
            let dy = Int32(location.y - last.y)
            let offset: Int32 = 100_000
            let relX = dx + (dx < 0 ? -offset : offset)
            let winDy = -dy
            let relY = winDy + (winDy < 0 ? -offset : offset)
            self.service.sendMouseEvent(x: relX, y: relY, wheel: 0, flags: 0x200)
        } else {
            self.service.sendMouseEvent(x: normalizedX, y: normalizedY, wheel: 0, flags: 0x200)
        }
        self.lastMouseLocation = location
    }

    private func consumeServiceEvents() async {
        for await event in self.service.events {
            if let mapped = self.mapServiceEvent(event) {
                self.continuation.yield(mapped)
            }
        }
    }

    private func mapServiceEvent(_ event: MWBCompatibilityEvent) -> MBTransportEvent? {
        switch event {
        case .connected(let peer):
            let id = self.uuid(for: peer.id)
            return .machineConnected(Machine(id: id, name: peer.name, state: .connected, mwbPeerID: peer.id))
        case .disconnected(let peer):
            guard let id = self.peerIDs[peer.id] else { return nil }
            return .machineDisconnected(id)
        case .remoteMouse(let mouseEvent):
            return .mwbMouse(mouseEvent)
        case .remoteKey(let keyEvent):
            return .mwbKey(keyEvent)
        case .machineSwitched(let peer):
            let id = peer.map { self.uuid(for: $0.id) }
            return .activeMachineChanged(id, peer?.name)
        case .machineMatrix(let matrix):
            return .arrangementReceived(matrix)
        case .matrixOptionsUpdated(let twoRow, let swap):
            return .arrangementOptionsUpdated(twoRow: twoRow, swap: swap)
        case .clipboardText(let text):
            return .clipboardText(text)
        case .clipboardImage(let data):
            return .clipboardImage(data)
        case .clipboardFiles(let urls):
            return .clipboardFiles(urls)
        case .hideMouse:
            return .hideMouse
        case .dragDropOperation(let sourceName):
            return .dragDropStateChanged(.dropping, sourceName: sourceName)
        case .dragDropBegin(let sourceName):
            return .dragDropStateChanged(.dragging, sourceName: sourceName)
        case .dragDropEnd:
            return .dragDropStateChanged(nil, sourceName: nil)
        case .captureScreen(let sourceID):
            return .screenCaptureRequested(sourceID)
        case .reconnectAttempt(let host):
            return .reconnectAttempt(host)
        case .reconnectStopped(let host):
            return .reconnectStopped(host)
        case .log(let message):
            return .log(message)
        case .error(let message):
            return .error(message)
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

@MainActor
private final class MBMouseCoalescer {
    private let clock: any ClockProviding
    private let flush: (EventSnapshot) -> Void
    private var pendingSnapshot: EventSnapshot?
    private var lastSendTime: TimeInterval = 0
    private let scheduledFlushTask = CancellableTaskSlot()
    private let minInterval: TimeInterval = 0.008

    init(clock: any ClockProviding, flush: @escaping (EventSnapshot) -> Void) {
        self.clock = clock
        self.flush = flush
    }

    deinit {
        self.scheduledFlushTask.cancel()
    }

    func update(snapshot: EventSnapshot) {
        self.pendingSnapshot = snapshot
        self.tryFlush()
    }

    func forceFlush(snapshot: EventSnapshot) {
        self.scheduledFlushTask.cancel()
        self.pendingSnapshot = nil
        self.lastSendTime = self.clock.now()
        self.flush(snapshot)
    }

    func cancel() {
        self.scheduledFlushTask.cancel()
        self.pendingSnapshot = nil
    }

    private func tryFlush() {
        let now = self.clock.now()
        let elapsed = now - self.lastSendTime
        if elapsed >= self.minInterval, let snapshot = self.pendingSnapshot {
            self.scheduledFlushTask.cancel()
            self.pendingSnapshot = nil
            self.lastSendTime = now
            self.flush(snapshot)
        } else if !self.scheduledFlushTask.isActive, self.pendingSnapshot != nil {
            let delay = max(0.001, self.minInterval - elapsed)
            let task = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.scheduledFlushTask.replace(with: nil)
                self.tryFlush()
            }
            self.scheduledFlushTask.replace(with: task)
        }
    }
}
