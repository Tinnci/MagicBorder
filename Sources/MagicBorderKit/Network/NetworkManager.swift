import AppKit
import Foundation
import Network
import Observation
import OSLog

@MainActor
@Observable
public class MBNetworkManager: Observation.Observable {
    public static let shared = MBNetworkManager()
    public static let localMachineUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()

    public struct MBToastState: Equatable {
        public let message: String
        public let systemImage: String
    }

    public enum SwitchState: String {
        case idle
        case switching
        case active
    }

    // Config
    let port: NWEndpoint.Port = 12345
    let serviceType = "_magicborder._tcp"

    public var connectedMachines: [Machine] = []

    // MARK: - Discovery (delegated to MBDiscoveryService)

    private var discoveryService: MBDiscoveryService?

    /// Mirror of `MBDiscoveryService.discoveredPeers` — kept as observable for the UI.
    public var discoveredPeers: [DiscoveredPeer] = []

    // Identity
    let localID = UUID()
    let localName = Host.current().localizedName ?? "Unknown Mac"
    let localNumericID: Int32 = .random(in: 1000 ... 999999)
    public var localDisplayName: String { self.localName }

    public var switchState: SwitchState = .idle
    public var activeMachineId: UUID? {
        didSet {
            MBInputManager.shared.setRemoteTarget(self.activeMachineId)
            if let id = activeMachineId,
               let machine = connectedMachines.first(where: { $0.id == id })
            {
                self.activeMachineName = machine.name
                self.switchState = .active
                self.showToast(
                    message: "已切换到 \(machine.name)",
                    systemImage: "arrow.right")
            } else {
                self.activeMachineName = self.localName
                self.switchState = .idle
                self.showToast(
                    message: "已切回本机",
                    systemImage: "arrow.left")
            }
        }
    }

    public var activeMachineName: String = Host.current().localizedName ?? "Local Mac"
    public var lastSwitchTimestamp: Date?
    public var toast: MBToastState?

    public var protocolMode: MBProtocolMode = .mwbCompatibility
    public var securityKey: String = "" {
        didSet {
            self.currentTransport.updateConfiguration(
                securityKey: self.securityKey,
                settings: self.compatibilitySettings)
        }
    }

    public var compatibilitySettings = MBCompatibilitySettings()

    public var pairingDebugLog: [String] = []
    public var pairingError: String?

    /// Spatial arrangement of machines in the grid.
    public var arrangement: MachineArrangement = .init()
    private var lastEdgeSwitchTime: TimeInterval = 0
    private var edgeSwitchLockedUntil: TimeInterval = 0
    private var edgeSwitchPendingRelease = false
    private var lastNoTargetDirection: EdgeDirection?
    private var lastNoTargetLogTime: TimeInterval = 0
    private var lastMouseLocation: CGPoint?
    private var toastTask: Task<Void, Never>?
    public var dragDropState: MBDragDropState?
    public var dragDropSourceName: String?
    public var dragDropFileSummary: String?
    public var dragDropProgress: Double?

    private var modernTransport: MBModernTransport!
    private var compatibilityTransport: MBMWBTransport!
    private var currentTransport: MBTransport {
        self.protocolMode == .modern ? self.modernTransport : self.compatibilityTransport
    }

    init() {
        let settings = MBCompatibilitySettings()
        self.compatibilitySettings = settings
        self.securityKey = ""
        self.connectedMachines = []
        self.discoveredPeers = []
        self.switchState = .idle
        self.activeMachineName = Host.current().localizedName ?? "Local Mac"
        self.pairingDebugLog = []
        self.pairingError = nil
        self.arrangement = .init()
        self.dragDropState = nil
        self.dragDropSourceName = nil
        self.dragDropFileSummary = nil
        self.dragDropProgress = nil

        self.modernTransport = MBModernTransport(
            serviceType: self.serviceType,
            localName: self.localName,
            localID: self.localID,
            securityKey: settings.securityKey)
        self.compatibilityTransport = MBMWBTransport(
            localName: self.localName,
            localID: self.localNumericID,
            settings: settings)

        // Pull persisted compatibility key instead of overwriting it with a placeholder.
        self.securityKey = settings.securityKey

        let svc = MBDiscoveryService(serviceType: serviceType, localName: localName)
        self.discoveryService = svc
        svc.startBrowsing()
        svc.startSubnetScanning()
        Task { @MainActor [weak self] in await self?.consumeDiscoveryEvents(svc) }

        // Break circular dep: InputManager calls back through MBInputRoutingDelegate.
        MBInputManager.shared.routingDelegate = self

        self.modernTransport.start()
        self.compatibilityTransport.start()
        Task { @MainActor [weak self] in await self?.consumeTransportEvents(self?.modernTransport) }
        Task { @MainActor [weak self] in await self?.consumeTransportEvents(self?.compatibilityTransport) }
        self.configureCompatibility()
        self.setupPasteboardMonitoring()
    }

    private func consumeDiscoveryEvents(_ svc: MBDiscoveryService) async {
        for await event in svc.events {
            switch event {
            case .found: self.discoveredPeers = svc.discoveredPeers
            case .lost: self.discoveredPeers = svc.discoveredPeers
            }
        }
    }

    private func consumeTransportEvents(_ transport: MBTransport?) async {
        guard let transport else { return }
        for await event in transport.events {
            switch event {
            case .machineConnected(let machine):
                if let index = self.connectedMachines.firstIndex(where: { $0.id == machine.id }) {
                    self.connectedMachines[index] = machine
                } else {
                    self.connectedMachines.append(machine)
                }
            case .machineDisconnected(let id):
                let disconnected = self.connectedMachines.first(where: { $0.id == id })
                self.connectedMachines.removeAll { $0.id == id }
                if self.activeMachineId == id {
                    self.forceReturnToLocal(reason: "disconnect")
                }
                if let disconnected {
                    self.showToast(message: "已断开 \(disconnected.name)", systemImage: "link.slash")
                }
            case .activeMachineChanged(let id, let name):
                self.activeMachineId = id
                self.activeMachineName = name ?? self.localName
                self.switchState = .active
                self.lastSwitchTimestamp = Date()
                if id == nil {
                    NSCursor.unhide()
                }
            case .arrangementReceived(let matrix):
                self.updateLocalMatrix(names: matrix)
            case .arrangementOptionsUpdated(let twoRow, let swap):
                self.compatibilitySettings.matrixOneRow = !twoRow
                self.compatibilitySettings.matrixCircle = swap
            case .remoteEvent(let event):
                MBInputManager.shared.simulateRemoteEvent(event)
            case .mwbMouse(let event):
                MBInputManager.shared.simulateMouseEvent(event)
            case .mwbKey(let event):
                MBInputManager.shared.simulateKeyEvent(event)
            case .clipboardText(let text):
                MBInputManager.shared.ignoreNextClipboardChange()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self.showToast(message: "收到剪贴板文本", systemImage: "doc.on.clipboard")
            case .clipboardImage(let data):
                MBInputManager.shared.ignoreNextClipboardChange()
                if let image = NSImage(data: data) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                    self.showToast(message: "收到剪贴板图片", systemImage: "photo")
                }
            case .clipboardFiles(let urls):
                MBInputManager.shared.ignoreNextClipboardChange()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects(urls as [NSURL])
                self.dragDropFileSummary = self.makeFileSummary(urls)
                self.dragDropProgress = 1.0
                self.showToast(message: "收到剪贴板文件", systemImage: "tray.and.arrow.down")
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1500000000)
                    self?.dragDropState = nil
                    self?.dragDropSourceName = nil
                    self?.dragDropFileSummary = nil
                    self?.dragDropProgress = nil
                }
            case .dragDropStateChanged(let state, let sourceName):
                self.dragDropState = state
                self.dragDropSourceName = sourceName
                if state == nil {
                    self.dragDropFileSummary = nil
                    self.dragDropProgress = nil
                } else {
                    self.dragDropProgress = nil
                }
            case .hideMouse:
                NSCursor.hide()
            case .screenCaptureRequested(let sourceID):
                self.sendScreenCapture(to: sourceID)
            case .reconnectAttempt(let host):
                self.showToast(message: "正在重连 \(host)", systemImage: "arrow.clockwise")
            case .reconnectStopped(let host):
                self.showToast(message: "已停止重连 \(host)", systemImage: "pause.circle")
            case .log(let message):
                self.appendPairingLog(message)
            case .error(let message):
                self.setPairingError(message)
            }
        }
    }

    public func appendPairingLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        self.pairingDebugLog.append("[\(timestamp)] \(message)")
        if self.pairingDebugLog.count > 200 {
            self.pairingDebugLog.removeFirst(self.pairingDebugLog.count - 200)
        }
    }

    public func setPairingError(_ message: String) {
        self.pairingError = message
        self.appendPairingLog("ERROR: \(message)")
    }

    public func clearPairingDiagnostics() {
        self.pairingError = nil
        self.pairingDebugLog.removeAll()
    }

    private func configureCompatibility() {
        self.currentTransport.updateConfiguration(
            securityKey: self.securityKey,
            settings: self.compatibilitySettings)
    }

    private func setupPasteboardMonitoring() {
        MBInputManager.shared.startClipboardSync()
    }

    public func handleLocalPasteboard(_ content: MBPasteboardContent) {
        guard self.compatibilitySettings.shareClipboard else { return }

        switch content {
        case .text(let text):
            self.sendClipboardText(text)
            self.showToast(message: "已同步剪贴板文本", systemImage: "doc.on.clipboard")
        case .image(let data):
            self.sendClipboardImage(data)
            self.showToast(message: "已同步剪贴板图片", systemImage: "photo")
        case .files(let urls):
            guard self.compatibilitySettings.transferFiles else { return }
            self.sendFileDrop(urls)
            self.showToast(message: "已同步剪贴板文件", systemImage: "tray.and.arrow.up")
        }
    }

    private func makeFileSummary(_ urls: [URL]) -> String? {
        guard !urls.isEmpty else { return nil }
        if urls.count == 1 {
            return urls[0].lastPathComponent
        }
        return "\(urls[0].lastPathComponent) +\(urls.count - 1)"
    }

    private func sendScreenCapture(to sourceId: Int32?) {
        guard let image = captureMainScreenPNG() else { return }
        self.compatibilityTransport.sendScreenCapture(image, to: sourceId)
    }

    private func captureMainScreenPNG() -> Data? {
        guard let screen = NSScreen.main,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
              as? NSNumber
        else { return nil }
        let displayId = CGDirectDisplayID(truncating: screenNumber)
        guard let cgImage = CGDisplayCreateImage(displayId) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    public func requestSwitch(to machineId: UUID, reason: SwitchReason = .manual) {
        guard let machine = self.connectedMachines.first(where: { $0.id == machineId }) else { return }
        if self.protocolMode == .modern {
            self.activeMachineId = machineId
            return
        }

        self.switchState = .switching
        self.showToast(
            message: "正在切换到 \(machine.name)", systemImage: "arrow.triangle.2.circlepath")
        self.compatibilityTransport.activate(machine: machine)
        if reason == .manual {
            self.setEdgeSwitchGuard()
            self.centerRemoteCursorIfPossible()
        }
    }

    public func forceReturnToLocal(reason: String) {
        if self.activeMachineId != nil {
            if self.protocolMode != .modern {
                self.compatibilityTransport.activate(machine: nil)
            }
            self.activeMachineId = nil
            self.switchState = .idle
            self.lastSwitchTimestamp = Date()
            NSCursor.unhide()
            self.appendPairingLog("Force return to local (\(reason))")
        }
    }

    public func showToast(
        message: String, systemImage: String = "arrow.left.arrow.right",
        duration: TimeInterval = 2.6)
    {
        self.toast = MBToastState(message: message, systemImage: systemImage)
        self.toastTask?.cancel()
        self.toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            await MainActor.run { [weak self] in
                self?.toast = nil
            }
        }
    }

    public func requestSwitch(toMachineNamed name: String, reason: SwitchReason = .manual) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized == self.localName.uppercased() {
            self.showToast(message: "正在切回本机", systemImage: "arrow.triangle.2.circlepath")
            self.activeMachineId = nil
            return
        }

        if let target = self.connectedMachines.first(where: { $0.name.uppercased() == normalized }) {
            self.requestSwitch(to: target.id, reason: reason)
        }
    }

    public func sendMachineMatrix(names: [String], twoRow: Bool = false, swap: Bool = false) {
        let uppercased = names.map { $0.uppercased() }
        self.updateLocalMatrix(names: uppercased)
        self.currentTransport.sendMachineMatrix(names: uppercased, twoRow: twoRow, swap: swap)
    }

    public func sendFileDrop(_ urls: [URL]) {
        self.currentTransport.sendFileDrop(urls)
    }

    public func presentFilePickerAndSend() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        let response = panel.runModal()
        if response == .OK {
            self.sendFileDrop(panel.urls)
        }
    }

    public func updateLocalMatrix(names: [String]) {
        let normalized = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        let uuids: [UUID] = normalized.compactMap { name in
            if name == self.localName.uppercased() { return MBNetworkManager.localMachineUUID }
            return self.connectedMachines.first(where: { $0.name.uppercased() == name })?.id
        }
        self.updateArrangement(machineIDs: uuids)
    }

    public func updateArrangement(machineIDs: [UUID]) {
        self.arrangement = MachineArrangement(
            slots: machineIDs,
            columns: self.compatibilitySettings.matrixOneRow ? max(1, machineIDs.count) : 2)
    }

    public func handleLocalMouseEvent(_ event: CGEvent, type: CGEventType) {
        let snapshot = EventSnapshot(from: event, type: type)
        self.handleLocalMouseEvent(snapshot: snapshot)
    }

    public func handleLocalMouseEvent(snapshot: EventSnapshot) {
        guard self.compatibilitySettings.switchByMouse else {
            MBLogger.network.debug("Edge check skipped: switchByMouse=false")
            return
        }
        guard self.activeMachineId == nil else {
            MBLogger.network.debug("Edge check skipped: activeMachineId != nil")
            return
        }
        guard let mainScreen = NSScreen.main ?? NSScreen.screens.first else {
            MBLogger.network.debug("Edge check skipped: no screen")
            return
        }

        let location = snapshot.location
        let threshold: CGFloat = 3

        // Quartz location.y (top-down) -> CocoaY (bottom-up)
        let cocoaY = mainScreen.frame.maxY - (location.y - mainScreen.frame.origin.y)
        let edgeLocation = CGPoint(x: location.x, y: cocoaY)
        let screen =
            NSScreen.screens.first(where: { $0.frame.contains(edgeLocation) }) ?? mainScreen
        let bounds = screen.frame

        let nearLeft = edgeLocation.x <= bounds.minX + threshold
        let nearRight = edgeLocation.x >= bounds.maxX - threshold
        let nearTop = edgeLocation.y >= bounds.maxY - threshold
        let nearBottom = edgeLocation.y <= bounds.minY + threshold

        if self.compatibilitySettings.blockCorners {
            let nearCorner = (nearLeft || nearRight) && (nearBottom || nearTop)
            if nearCorner { return }
        }

        let direction: EdgeDirection? =
            if nearLeft {
                .left
            } else if nearRight {
                .right
            } else if nearTop {
                .up
            } else if nearBottom {
                .down
            } else {
                nil
            }

        if self.edgeSwitchPendingRelease {
            if self.isAwayFromEdges(
                location: edgeLocation,
                bounds: bounds,
                margin: CGFloat(self.compatibilitySettings.edgeSwitchSafeMargin))
            {
                self.edgeSwitchPendingRelease = false
            } else {
                MBLogger.network.debug("Edge check skipped: pending release")
                return
            }
        }

        let now = CFAbsoluteTimeGetCurrent()
        if now < self.edgeSwitchLockedUntil {
            MBLogger.network.debug("Edge check skipped: locked")
            return
        }

        guard let dir = direction else {
            MBLogger.network.debug("Edge check: not near edge")
            return
        }

        let effectiveArrangement = self.effectiveArrangement()
        let arDir = self.arrangementDirection(for: dir)

        guard let targetId = effectiveArrangement.next(
            from: MBNetworkManager.localMachineUUID,
            direction: arDir,
            wraps: compatibilitySettings.matrixCircle,
            oneRow: compatibilitySettings.matrixOneRow)
        else {
            let now2 = CFAbsoluteTimeGetCurrent()
            let shouldLog = self.lastNoTargetDirection != dir || now2 - self.lastNoTargetLogTime > 1.0
            if shouldLog {
                self.lastNoTargetDirection = dir
                self.lastNoTargetLogTime = now2
                MBLogger.network.debug("Edge check: no target for direction")
            }
            return
        }

        if now - self.lastEdgeSwitchTime < 0.1 {
            MBLogger.network.debug("Edge check skipped: throttled")
            return
        }
        self.lastEdgeSwitchTime = now
        self.setEdgeSwitchGuard()

        MBLogger.network.info("Edge switch triggered: \(String(describing: dir)) towards \(targetId)")
        if targetId == MBNetworkManager.localMachineUUID {
            self.forceReturnToLocal(reason: "edge")
        } else {
            self.requestSwitch(to: targetId, reason: .edge)
        }
    }

    public func handleRemoteMouseEvent(snapshot: EventSnapshot) {
        guard self.compatibilitySettings.switchByMouse else { return }
        guard self.activeMachineId != nil else { return }
        guard let mainScreen = NSScreen.main ?? NSScreen.screens.first else { return }

        let location = snapshot.location
        let threshold: CGFloat = 3

        // Quartz location.y (top-down) -> CocoaY (bottom-up)
        let cocoaY = mainScreen.frame.maxY - (location.y - mainScreen.frame.origin.y)
        let edgeLocation = CGPoint(x: location.x, y: cocoaY)
        let screen =
            NSScreen.screens.first(where: { $0.frame.contains(edgeLocation) }) ?? mainScreen
        let bounds = screen.frame

        let nearLeft = edgeLocation.x <= bounds.minX + threshold
        let nearRight = edgeLocation.x >= bounds.maxX - threshold
        let nearTop = edgeLocation.y >= bounds.maxY - threshold
        let nearBottom = edgeLocation.y <= bounds.minY + threshold

        if self.compatibilitySettings.blockCorners {
            let nearCorner = (nearLeft || nearRight) && (nearBottom || nearTop)
            if nearCorner { return }
        }

        let direction: EdgeDirection? =
            if nearLeft {
                .left
            } else if nearRight {
                .right
            } else if nearTop {
                .up
            } else if nearBottom {
                .down
            } else {
                nil
            }

        if self.edgeSwitchPendingRelease {
            if self.isAwayFromEdges(
                location: edgeLocation,
                bounds: bounds,
                margin: CGFloat(self.compatibilitySettings.edgeSwitchSafeMargin))
            {
                self.edgeSwitchPendingRelease = false
            } else {
                return
            }
        }

        let now = CFAbsoluteTimeGetCurrent()
        if now < self.edgeSwitchLockedUntil { return }
        if now - self.lastEdgeSwitchTime < 0.1 { return }
        self.lastEdgeSwitchTime = now
        self.setEdgeSwitchGuard()

        if let dir = direction, let activeId = activeMachineId {
            let effectiveArrangement = self.effectiveArrangement()
            let arDir = self.arrangementDirection(for: dir)
            if let targetId = effectiveArrangement.next(
                from: activeId, direction: arDir,
                wraps: compatibilitySettings.matrixCircle,
                oneRow: compatibilitySettings.matrixOneRow)
            {
                MBLogger.network.info(
                    "Remote edge switch: \(String(describing: dir)) → \(targetId)")
                if targetId == MBNetworkManager.localMachineUUID {
                    self.forceReturnToLocal(reason: "edge")
                } else {
                    self.requestSwitch(to: targetId, reason: .edge)
                }
                return
            }
        }

        if direction != nil {
            self.forceReturnToLocal(reason: "edge")
        }
    }

    private enum EdgeDirection {
        case left
        case right
        case up
        case down
    }

    public enum SwitchReason {
        case manual
        case edge
    }

    private func setEdgeSwitchGuard() {
        let now = CFAbsoluteTimeGetCurrent()
        let lockSeconds = max(0.05, self.compatibilitySettings.edgeSwitchLockSeconds)
        self.edgeSwitchLockedUntil = now + lockSeconds
        self.edgeSwitchPendingRelease = true
    }

    private func isAwayFromEdges(location: CGPoint, bounds: CGRect, margin: CGFloat) -> Bool {
        let awayLeft = location.x > bounds.minX + margin
        let awayRight = location.x < bounds.maxX - margin
        let awayBottom = location.y > bounds.minY + margin
        let awayTop = location.y < bounds.maxY - margin
        return awayLeft && awayRight && awayBottom && awayTop
    }

    private func centerRemoteCursorIfPossible() {
        guard self.protocolMode != .modern else { return }
        guard !self.compatibilitySettings.moveMouseRelatively else { return }
        guard self.compatibilitySettings.centerCursorOnManualSwitch else { return }
        self.compatibilityTransport.centerRemoteCursor()
    }

    private func arrangementDirection(for direction: EdgeDirection) -> ArrangementDirection {
        switch direction {
        case .left:
            .left
        case .right:
            .right
        case .up:
            .up
        case .down:
            .down
        }
    }

    private func effectiveArrangement() -> MachineArrangement {
        let validIDs = Set([MBNetworkManager.localMachineUUID] + self.connectedMachines.map(\.id))

        var slots = self.arrangement.slots.filter { validIDs.contains($0) }
        for id in [MBNetworkManager.localMachineUUID] + self.connectedMachines.map(\.id) where !slots
            .contains(id)
        {
            slots.append(id)
        }

        return MachineArrangement(
            slots: slots,
            columns: self.compatibilitySettings.matrixOneRow ? max(1, slots.count) : max(1, self.arrangement.columns))
    }

    // MARK: - Connection Handling

    public func connect(to result: NWBrowser.Result) {
        self.currentTransport.connect(to: result)
    }

    public func connect(to endpoint: NWEndpoint) {
        self.currentTransport.connect(to: endpoint)
    }

    public func connectToHost(ip: String, port: UInt16 = 15101) {
        guard !ip.isEmpty else { return }
        self.showToast(message: "正在连接 \(ip)", systemImage: "arrow.right.circle")
        self.currentTransport.connectToHost(ip: ip, port: port)
    }

    public func disconnect(machineId: UUID) {
        guard let machine = self.connectedMachines.first(where: { $0.id == machineId }) else { return }
        self.currentTransport.disconnect(machine: machine)
    }

    public func reconnect(machineId: UUID) {
        guard let machine = self.connectedMachines.first(where: { $0.id == machineId }) else { return }
        self.currentTransport.reconnect(machine: machine)
    }

    public func applyCompatibilitySettings() {
        self.securityKey = self.compatibilitySettings.securityKey
        self.currentTransport.updateConfiguration(
            securityKey: self.securityKey,
            settings: self.compatibilitySettings)
    }

    public func sendRemoteInput(event: CGEvent, type: CGEventType) {
        let snapshot = EventSnapshot(from: event, type: type)
        self.sendRemoteInput(snapshot: snapshot)
    }

    public func sendRemoteInput(snapshot: EventSnapshot) {
        self.currentTransport.sendRemoteInput(snapshot: snapshot, activeMachineId: self.activeMachineId)
    }

    private func sendClipboardText(_ text: String) {
        self.currentTransport.sendClipboardText(text, activeMachineId: self.activeMachineId)
    }

    private func sendClipboardImage(_ data: Data) {
        self.currentTransport.sendClipboardImage(data, activeMachineId: self.activeMachineId)
    }
}

// MARK: - MBInputRoutingDelegate

extension MBNetworkManager: MBInputRoutingDelegate {}
