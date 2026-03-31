import AppKit
import CryptoKit
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

    // MARK: - Connection Registry

    private var registry: MBConnectionRegistry?

    /// Forwarded from registry — observable for the UI and for sending.
    public var peers: [NWConnection] { self.registry?.peers ?? [] }

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
            self.compatibilityService?.updateSecurityKey(self.securityKey)
        }
    }

    public var compatibilitySettings = MBCompatibilitySettings()

    public var pairingDebugLog: [String] = []
    public var pairingError: String?

    private var localMatrix: [String] = []
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

    private var compatibilityService: MWBCompatibilityService?

    // Mouse Coalescing
    private var mouseCoalescer: MouseCoalescer?

    init() {
        // Pull persisted compatibility key instead of overwriting it with a placeholder.
        self.securityKey = self.compatibilitySettings.securityKey

        let reg = MBConnectionRegistry(serviceType: serviceType, localName: localName)
        self.registry = reg
        reg.startListening()
        Task { @MainActor [weak self] in await self?.consumeConnectionEvents(reg) }

        let svc = MBDiscoveryService(serviceType: serviceType, localName: localName)
        self.discoveryService = svc
        svc.startBrowsing()
        svc.startSubnetScanning()
        Task { @MainActor [weak self] in await self?.consumeDiscoveryEvents(svc) }

        self.configureCompatibility()
        self.setupPasteboardMonitoring()
        // Ensure coalescer is initialized
        self.mouseCoalescer = MouseCoalescer(manager: self)
    }

    private func consumeDiscoveryEvents(_ svc: MBDiscoveryService) async {
        for await event in svc.events {
            switch event {
            case .found: self.discoveredPeers = svc.discoveredPeers
            case .lost: self.discoveredPeers = svc.discoveredPeers
            }
        }
    }

    private func consumeConnectionEvents(_ reg: MBConnectionRegistry) async {
        for await event in reg.events {
            switch event {
            case .connectionReady(let conn):
                Task {
                    self.sendHandshake(connection: conn)
                    self.receiveLoop(connection: conn)
                }
            case .connectionLost(let conn):
                if let id = reg.machineId(for: conn) {
                    self.connectedMachines.removeAll { $0.id == id }
                    if self.activeMachineId == id { self.activeMachineId = nil }
                }
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
        guard self.protocolMode != .modern else { return }
        let service = MWBCompatibilityService(
            localName: localName,
            localId: localNumericID,
            messagePort: compatibilitySettings.messagePort,
            clipboardPort: self.compatibilitySettings.clipboardPort)
        service.onLog = { [weak self] message in
            self?.appendPairingLog(message)
        }
        service.onError = { [weak self] message in
            self?.setPairingError(message)
        }
        service.onConnected = { [weak self] peer in
            guard let self else { return }
            if !self.connectedMachines.contains(where: { $0.mwbPeerID == peer.id }) {
                let machine = Machine(
                    id: UUID(),
                    name: peer.name,
                    state: .connected,
                    mwbPeerID: peer.id)
                self.connectedMachines.append(machine)
            }
            self.showToast(message: "已连接 \(peer.name)", systemImage: "link")
        }
        service.onDisconnected = { [weak self] peer in
            guard let self else { return }
            let disconnectedId = self.connectedMachines.first(where: { $0.mwbPeerID == peer.id })?.id
            self.connectedMachines.removeAll { $0.mwbPeerID == peer.id }
            if let id = disconnectedId, self.activeMachineId == id {
                self.forceReturnToLocal(reason: "disconnect")
            }
            self.showToast(message: "已断开 \(peer.name)", systemImage: "link.slash")
        }
        service.onReconnectAttempt = { [weak self] host in
            self?.showToast(message: "正在重连 \(host)", systemImage: "arrow.clockwise")
        }
        service.onReconnectStopped = { [weak self] host in
            self?.showToast(message: "已停止重连 \(host)", systemImage: "pause.circle")
        }
        service.onRemoteMouse = { event in
            MBInputManager.shared.simulateMouseEvent(event)
        }
        service.onRemoteKey = { event in
            MBInputManager.shared.simulateKeyEvent(event)
        }
        service.onMachineMatrix = { [weak self] matrix in
            self?.updateLocalMatrix(names: matrix)
        }
        service.onMatrixOptions = { [weak self] twoRow, swap in
            guard let self else { return }
            self.compatibilitySettings.matrixOneRow = !twoRow
            self.compatibilitySettings.matrixCircle = swap
        }
        service.onClipboardText = { text in
            MBInputManager.shared.ignoreNextClipboardChange()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            self.showToast(message: "收到剪贴板文本", systemImage: "doc.on.clipboard")
        }
        service.onClipboardImage = { data in
            MBInputManager.shared.ignoreNextClipboardChange()
            if let image = NSImage(data: data) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                self.showToast(message: "收到剪贴板图片", systemImage: "photo")
            }
        }
        service.onClipboardFiles = { urls in
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
        }
        service.onMachineSwitched = { [weak self] peer in
            guard let self else { return }
            if let peer {
                self.activeMachineId = self.uuid(for: peer.id)
                self.activeMachineName = peer.name
            } else {
                self.activeMachineId = nil
                self.activeMachineName = self.localName
                NSCursor.unhide()
            }
            self.switchState = .active
            self.lastSwitchTimestamp = Date()
        }
        service.onHideMouse = {
            NSCursor.hide()
        }
        service.onDragDropBegin = { [weak self] sourceName in
            guard let self else { return }
            self.dragDropState = .dragging
            self.dragDropSourceName = sourceName
            self.dragDropFileSummary = nil
            self.dragDropProgress = nil
        }
        service.onDragDropOperation = { [weak self] sourceName in
            guard let self else { return }
            self.dragDropState = .dropping
            self.dragDropSourceName = sourceName
            self.dragDropProgress = nil
        }
        service.onDragDropEnd = { [weak self] in
            guard let self else { return }
            self.dragDropState = nil
            self.dragDropSourceName = nil
            self.dragDropFileSummary = nil
            self.dragDropProgress = nil
        }
        service.onCaptureScreen = { [weak self] sourceId in
            self?.sendScreenCapture(to: sourceId)
        }
        self.compatibilityService = service

        // Only start when the key is valid to avoid spamming remote hosts with bad magic numbers.
        if self.compatibilitySettings.validateSecurityKey() {
            service.start(securityKey: self.securityKey)
        } else {
            self.appendPairingLog("Compatibility mode not started: security key invalid")
        }
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
        self.compatibilityService?.sendClipboardImage(image, to: sourceId)
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

    private func uuid(for mwbID: Int32) -> UUID {
        if let existing = connectedMachines.first(where: { $0.mwbPeerID == mwbID }) {
            return existing.id
        }
        return UUID()
    }

    private func mwbId(for name: String) -> Int32? {
        self.connectedMachines.first(where: { $0.name.uppercased() == name })?.mwbPeerID
    }

    public func requestSwitch(to machineId: UUID, reason: SwitchReason = .manual) {
        if self.protocolMode == .modern {
            // Native Switching
            self.activeMachineId = machineId
            return
        }

        guard let mwbId = connectedMachines.first(where: { $0.id == machineId })?.mwbPeerID else { return }
        self.switchState = .switching
        if let machine = connectedMachines.first(where: { $0.id == machineId }) {
            self.showToast(
                message: "正在切换到 \(machine.name)", systemImage: "arrow.triangle.2.circlepath")
        }
        self.compatibilityService?.sendNextMachine(targetId: mwbId)
        if reason == .manual {
            self.setEdgeSwitchGuard()
            self.centerRemoteCursorIfPossible()
        }
    }

    public func forceReturnToLocal(reason: String) {
        if self.activeMachineId != nil {
            if self.protocolMode != .modern {
                self.compatibilityService?.sendNextMachine(targetId: nil)
                self.compatibilityService?.stopAutoReconnect()
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

        if self.protocolMode != .mwbCompatibility {
            if let target = connectedMachines.first(where: { $0.name.uppercased() == normalized }) {
                self.activeMachineId = target.id
            }
        }

        if self.protocolMode != .modern {
            if let mwbId = mwbId(for: normalized) {
                self.showToast(
                    message: "正在切换到 \(normalized)", systemImage: "arrow.triangle.2.circlepath")
                self.compatibilityService?.sendNextMachine(targetId: mwbId)
                self.activeMachineId = self.uuid(for: mwbId)
                if reason == .manual {
                    self.setEdgeSwitchGuard()
                    self.centerRemoteCursorIfPossible()
                }
            }
        }
    }

    public func sendMachineMatrix(names: [String], twoRow: Bool = false, swap: Bool = false) {
        guard self.protocolMode != .modern else { return }
        let uppercased = names.map { $0.uppercased() }
        self.updateLocalMatrix(names: uppercased)
        self.compatibilityService?.sendMachineMatrix(uppercased, twoRow: twoRow, swap: swap)
    }

    public func sendFileDrop(_ urls: [URL]) {
        guard self.protocolMode != .modern else { return }
        self.compatibilityService?.sendFileDrop(urls)
    }

    public func presentFilePickerAndSend() {
        guard self.protocolMode != .modern else { return }

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
        self.localMatrix = names.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
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

        guard let dir = direction, let target = nextMachineName(for: dir, from: self.localName)
        else {
            if direction == nil {
                MBLogger.network.debug("Edge check: not near edge")
            } else {
                let now = CFAbsoluteTimeGetCurrent()
                let shouldLog = self.lastNoTargetDirection != direction
                    || now - self.lastNoTargetLogTime > 1.0
                if shouldLog {
                    self.lastNoTargetDirection = direction
                    self.lastNoTargetLogTime = now
                    MBLogger.network.debug("Edge check: no target for direction")
                }
            }
            return
        }

        if now - self.lastEdgeSwitchTime < 0.1 {
            MBLogger.network.debug("Edge check skipped: throttled")
            return
        }
        self.lastEdgeSwitchTime = now
        self.setEdgeSwitchGuard()

        MBLogger.network.info("Edge switch triggered: \(String(describing: dir)) towards \(target)")
        self.requestSwitch(toMachineNamed: target, reason: .edge)
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

        if let dir = direction,
           let target = nextMachineName(for: dir, from: self.activeMachineName)
        {
            MBLogger.network.info(
                "Remote edge switch triggered: \(String(describing: dir)) towards \(target)")
            self.requestSwitch(toMachineNamed: target, reason: .edge)
            return
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
        self.compatibilityService?.sendMouseEvent(x: 32767, y: 32767, wheel: 0, flags: 0x200)
    }

    private func nextMachineName(for direction: EdgeDirection, from currentName: String) -> String? {
        var matrix = self.localMatrix
        if matrix.isEmpty {
            matrix =
                [self.localName.uppercased()] + self.connectedMachines.map { $0.name.uppercased() }
        }

        guard let currentIndex = matrix.firstIndex(of: currentName.uppercased()) else { return nil }

        if self.compatibilitySettings.matrixOneRow {
            switch direction {
            case .left:
                let next = currentIndex - 1
                if next >= 0 { return matrix[next] }
                return self.compatibilitySettings.matrixCircle ? matrix.last : nil
            case .right:
                let next = currentIndex + 1
                if next < matrix.count { return matrix[next] }
                return self.compatibilitySettings.matrixCircle ? matrix.first : nil
            default:
                return nil
            }
        }

        let columns = 2
        let row = currentIndex / columns
        let col = currentIndex % columns
        let rows = Int(ceil(Double(matrix.count) / Double(columns)))

        var newRow = row
        var newCol = col

        switch direction {
        case .left:
            newCol -= 1
        case .right:
            newCol += 1
        case .up:
            newRow -= 1
        case .down:
            newRow += 1
        }

        if self.compatibilitySettings.matrixCircle {
            if newCol < 0 { newCol = columns - 1 }
            if newCol >= columns { newCol = 0 }
            if newRow < 0 { newRow = rows - 1 }
            if newRow >= rows { newRow = 0 }
        }

        let newIndex = newRow * columns + newCol
        guard newIndex >= 0, newIndex < matrix.count else { return nil }
        return matrix[newIndex]
    }

    // MARK: - Connection Handling

    public func connect(to result: NWBrowser.Result) {
        self.registry?.connect(to: result)
    }

    public func connect(to endpoint: NWEndpoint) {
        self.registry?.connect(to: endpoint)
    }

    public func connectToHost(ip: String, port: UInt16 = 15101) {
        guard !ip.isEmpty else { return }
        if self.protocolMode != .modern {
            self.showToast(message: "正在连接 \(ip)", systemImage: "arrow.right.circle")
            self.compatibilityService?.connectToHost(
                ip: ip,
                messagePort: self.compatibilitySettings.messagePort,
                clipboardPort: self.compatibilitySettings.clipboardPort)
            return
        }
        self.showToast(message: "正在连接 \(ip)", systemImage: "arrow.right.circle")
        self.registry?.connectToHost(ip, port: port)
    }

    public func disconnect(machineId: UUID) {
        self.registry?.disconnect(machineId: machineId)
        self.connectedMachines.removeAll { $0.id == machineId }
        if self.activeMachineId == machineId { self.activeMachineId = nil }
    }

    public func reconnect(machineId: UUID) {
        self.connectedMachines.removeAll { $0.id == machineId }
        self.registry?.reconnect(machineId: machineId)
    }

    public func applyCompatibilitySettings() {
        self.securityKey = self.compatibilitySettings.securityKey

        guard self.compatibilitySettings.validateSecurityKey() else {
            self.compatibilityService?.stop()
            self.appendPairingLog("Compatibility mode stopped: security key invalid")
            return
        }

        self.compatibilityService?.updatePorts(
            messagePort: self.compatibilitySettings.messagePort,
            clipboardPort: self.compatibilitySettings.clipboardPort)
    }

    // MARK: - Sending

    func sendHandshake(connection: NWConnection) {
        var info = MachineInfo(
            id: localID,
            name: localName,
            screenWidth: Double(NSScreen.main?.frame.width ?? 0),
            screenHeight: Double(NSScreen.main?.frame.height ?? 0),
            signature: nil)

        // Compute Signature
        if let keyData = securityKey.data(using: .utf8),
           let idData = info.id.uuidString.data(using: .utf8)
        {
            let key = SymmetricKey(data: keyData)
            let signature = HMAC<SHA256>.authenticationCode(for: idData, using: key)
            info.signature = Data(signature).base64EncodedString()
        }

        let packet = PacketType.handshake(info: info)
        self.send(packet, to: connection)
    }

    func broadcast(_ event: RemoteEvent) {
        self.sendRemoteEvent(event)
    }

    public func sendRemoteInput(event: CGEvent, type: CGEventType) {
        let snapshot = EventSnapshot(from: event, type: type)
        self.sendRemoteInput(snapshot: snapshot)
    }

    public func sendRemoteInput(snapshot: EventSnapshot) {
        switch self.protocolMode {
        case .modern:
            if let remoteEvent = MBInputManager.shared.convertToRemoteEvent(snapshot: snapshot) {
                self.sendRemoteEvent(remoteEvent)
            }
        case .mwbCompatibility:
            self.sendCompatibilityInput(snapshot: snapshot)
        }
    }

    private func sendRemoteEvent(_ event: RemoteEvent) {
        let packet = PacketType.inputEvent(event)
        if let active = activeConnection() {
            self.send(packet, to: active)
        } else {
            for peer in self.peers {
                self.send(packet, to: peer)
            }
        }
    }

    private func activeConnection() -> NWConnection? {
        self.registry?.activeConnection(activeMachineId: self.activeMachineId)
    }

    private func sendCompatibilityInput(event: CGEvent, type: CGEventType) {
        let snapshot = EventSnapshot(from: event, type: type)
        self.sendCompatibilityInput(snapshot: snapshot)
    }

    private func sendCompatibilityInput(snapshot: EventSnapshot) {
        switch snapshot.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            self.mouseCoalescer?.update(snapshot: snapshot)
        default:
            self.mouseCoalescer?.forceFlush(snapshot: snapshot)
        }
    }

    fileprivate func sendCompatibilityInputInternal(snapshot: EventSnapshot) {
        guard let screen = NSScreen.main else { return }
        let bounds = screen.frame
        let location = snapshot.location

        let normalizedX = Int32(((location.x - bounds.minX) / bounds.width) * 65535.0)
        let normalizedY = Int32(((location.y - bounds.minY) / bounds.height) * 65535.0)

        switch snapshot.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            if self.compatibilitySettings.moveMouseRelatively, let last = lastMouseLocation {
                let dx = Int32(location.x - last.x)
                let dy = Int32(location.y - last.y)
                let offset: Int32 = 100000
                let relX = dx + (dx < 0 ? -offset : offset)
                let winDy = -dy
                let relY = winDy + (winDy < 0 ? -offset : offset)
                self.compatibilityService?.sendMouseEvent(x: relX, y: relY, wheel: 0, flags: 0x200)
            } else {
                self.compatibilityService?.sendMouseEvent(
                    x: normalizedX, y: normalizedY, wheel: 0, flags: 0x200)
            }
            self.lastMouseLocation = location
        case .leftMouseDown:
            self.compatibilityService?.sendMouseEvent(
                x: normalizedX, y: normalizedY, wheel: 0, flags: 0x201)
        case .leftMouseUp:
            self.compatibilityService?.sendMouseEvent(
                x: normalizedX, y: normalizedY, wheel: 0, flags: 0x202)
        case .rightMouseDown:
            self.compatibilityService?.sendMouseEvent(
                x: normalizedX, y: normalizedY, wheel: 0, flags: 0x204)
        case .rightMouseUp:
            self.compatibilityService?.sendMouseEvent(
                x: normalizedX, y: normalizedY, wheel: 0, flags: 0x205)
        case .scrollWheel:
            let deltaY = Int32(snapshot.scrollDeltaY)
            self.compatibilityService?.sendMouseEvent(
                x: normalizedX, y: normalizedY, wheel: deltaY, flags: 0x20A)
        case .keyDown:
            if let key = MBInputManager.shared.windowsKeyCode(for: CGKeyCode(snapshot.keyCode)) {
                MBLogger.input.debug("Send keyDown: mac=\(snapshot.keyCode) -> win=\(key)")
                self.compatibilityService?.sendKeyEvent(keyCode: key, flags: 0)
            } else {
                MBLogger.input.warning("Unknown mac keyDown: \(snapshot.keyCode)")
            }
        case .keyUp:
            if let key = MBInputManager.shared.windowsKeyCode(for: CGKeyCode(snapshot.keyCode)) {
                MBLogger.input.debug("Send keyUp: mac=\(snapshot.keyCode) -> win=\(key)")
                self.compatibilityService?.sendKeyEvent(keyCode: key, flags: 0x80)
            } else {
                MBLogger.input.warning("Unknown mac keyUp: \(snapshot.keyCode)")
            }
        case .flagsChanged:
            let macKey = CGKeyCode(snapshot.keyCode)
            guard let key = MBInputManager.shared.windowsKeyCode(for: macKey) else {
                MBLogger.input.warning("Unknown mac flagsChanged: \(snapshot.keyCode)")
                break
            }
            let isDown: Bool =
                switch macKey {
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
            MBLogger.input.debug(
                "Send flagsChanged: mac=\(snapshot.keyCode) -> win=\(key) isDown=\(isDown)")
            self.compatibilityService?.sendKeyEvent(keyCode: key, flags: isDown ? 0 : 0x80)
        default:
            break
        }
    }

    private func send(_ packet: PacketType, to connection: NWConnection) {
        do {
            let data = try JSONEncoder().encode(packet)

            // Length-prefix framing
            var length = UInt32(data.count)
            let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)

            connection.send(
                content: lengthData + data,
                completion: .contentProcessed { error in
                    if let error {
                        MBLogger.network.error("Send error: \(error)")
                    }
                })
        } catch {
            MBLogger.network.error("Encoding error: \(error)")
        }
    }

    private func sendClipboardText(_ text: String) {
        if self.protocolMode != .mwbCompatibility {
            let payload = ClipboardPayload(content: Data(text.utf8), type: .text)
            self.sendClipboardPayload(payload)
        }
        if self.protocolMode != .modern {
            self.compatibilityService?.sendClipboardText(text)
        }
    }

    private func sendClipboardImage(_ data: Data) {
        if self.protocolMode != .mwbCompatibility {
            let payload = ClipboardPayload(content: data, type: .image)
            self.sendClipboardPayload(payload)
        }
        if self.protocolMode != .modern {
            self.compatibilityService?.sendClipboardImage(data)
        }
    }

    private func sendClipboardPayload(_ payload: ClipboardPayload) {
        let packet = PacketType.clipboardData(payload)
        if let active = activeConnection() {
            self.send(packet, to: active)
        } else {
            for peer in self.peers {
                self.send(packet, to: peer)
            }
        }
    }

    // MARK: - Receiving

    private func receiveLoop(connection: NWConnection) {
        // Read Length (4 bytes)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) {
            [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let error {
                MBLogger.network.error("Receive error: \(error)")
                return
            }

            if isComplete {
                MBLogger.network.info("Connection closed by peer")
                return
            }

            guard let content, content.count == 4 else {
                return // Wait for more
            }

            let length = content.withUnsafeBytes { $0.load(as: UInt32.self) }

            // Read Body
            Task {
                await self.receiveBody(connection: connection, length: Int(length))
            }
        }
    }

    private func receiveBody(connection: NWConnection, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) {
            [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let content {
                Task {
                    await self.handlePacketData(content, from: connection)
                }
            }

            if !isComplete, error == nil {
                // Continue loop
                Task {
                    await self.receiveLoop(connection: connection)
                }
            }
        }
    }

    private func handlePacketData(_ data: Data, from connection: NWConnection) {
        do {
            let packet = try JSONDecoder().decode(PacketType.self, from: data)
            switch packet {
            case .handshake(let info):
                MBLogger.network.info("Handshake from \(info.name)")

                // Verify Signature
                if let signature = info.signature,
                   let keyData = securityKey.data(using: .utf8),
                   let idData = info.id.uuidString.data(using: .utf8)
                {
                    let key = SymmetricKey(data: keyData)
                    let computed = HMAC<SHA256>.authenticationCode(for: idData, using: key)
                    let computedString = Data(computed).base64EncodedString()

                    if signature != computedString {
                        MBLogger.security.error(
                            "Invalid signature from \(info.name). Dropping connection.")
                        connection.cancel()
                        return
                    }
                    MBLogger.security.info("Verified signature from \(info.name)")
                } else {
                    // Legacy or unsecured fallback (Optional: enforce strict mode)
                    MBLogger.security.warning("No signature from \(info.name).")
                }

                if !self.connectedMachines.contains(where: { $0.id == info.id }) {
                    let machine = Machine(
                        id: info.id,
                        name: info.name,
                        state: .connected,
                        screenSize: CGSize(width: info.screenWidth, height: info.screenHeight))
                    self.connectedMachines.append(machine)
                    self.registry?.register(connection, for: info.id)
                }
            case .inputEvent(let event):
                // Handle remote input
                Task { @MainActor in
                    MBInputManager.shared.simulateRemoteEvent(event)
                }
            case .clipboardData(let payload):
                Task { @MainActor in
                    MBInputManager.shared.ignoreNextClipboardChange()
                    switch payload.type {
                    case .text:
                        if let text = String(data: payload.content, encoding: .utf8) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            self.showToast(message: "收到剪贴板文本", systemImage: "doc.on.clipboard")
                        }
                    case .image:
                        if let image = NSImage(data: payload.content) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([image])
                            self.showToast(message: "收到剪贴板图片", systemImage: "photo")
                        }
                    }
                }
            default:
                break
            }
        } catch {
            MBLogger.network.error("Decoding error: \(error.localizedDescription)")
        }
    }
}

private final class MouseCoalescer: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.magicborder.mouse.coalescing", qos: .userInteractive)
    private weak var manager: MBNetworkManager?

    // Coalescing State
    private var pendingSnapshot: EventSnapshot?
    private var isScheduled = false
    private var lastSendTime: CFAbsoluteTime = 0
    private let minInterval: TimeInterval = 0.008 // ~125 Hz

    init(manager: MBNetworkManager) {
        self.manager = manager
    }

    func update(snapshot: EventSnapshot) {
        self.queue.async {
            self.pendingSnapshot = snapshot
            self.tryFlush()
        }
    }

    func forceFlush(snapshot: EventSnapshot) {
        self.queue.sync {
            // Clear pending to avoid double send
            self.pendingSnapshot = nil
            // Update time to throttle subsequent implicit updates
            self.lastSendTime = CFAbsoluteTimeGetCurrent()

            Task { @MainActor in
                self.manager?.sendCompatibilityInputInternal(snapshot: snapshot)
            }
        }
    }

    private func tryFlush() {
        // If a flush is already pending in the queue, we just updated the snapshot
        // and let the scheduled block handle it.
        guard !self.isScheduled else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - self.lastSendTime

        if elapsed >= self.minInterval {
            // Ready to send immediately
            self.performFlush()
        } else {
            // Must wait
            let delay = self.minInterval - elapsed
            self.isScheduled = true
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.isScheduled = false
                self.performFlush()
            }
        }
    }

    private func performFlush() {
        guard let snapshot = self.pendingSnapshot else { return }
        self.pendingSnapshot = nil
        self.lastSendTime = CFAbsoluteTimeGetCurrent()

        Task { @MainActor in
            self.manager?.sendCompatibilityInputInternal(snapshot: snapshot)
        }
    }

    func stop() {
        // No persistent timer to stop
    }
}
