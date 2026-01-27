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

    // Browser & Listener
    private var listener: NWListener?
    private var browser: NWBrowser?

    // Connections
    public var peers: [NWConnection] = []

    public struct ConnectedMachine: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let connection: NWConnection

        public static func == (lhs: ConnectedMachine, rhs: ConnectedMachine) -> Bool {
            lhs.id == rhs.id
        }
    }

    public var connectedMachines: [ConnectedMachine] = []

    public var availablePeers: [NWBrowser.Result] = []

    // Unified Discovery
    public struct DiscoveredPeer: Identifiable, Equatable, Hashable {
        public let id = UUID()
        public let name: String
        public let endpoint: NWEndpoint
        public let type: PeerType

        public enum PeerType {
            case bonjour
            case manual
            case scanned
        }

        // Manual conformance if needed, but synthesis should work for simple types
        public static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
            lhs.name == rhs.name && lhs.endpoint == rhs.endpoint
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.name)
            hasher.combine(self.endpoint)
        }
    }

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

    public var protocolMode: MBProtocolMode = .dual
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
    private var lastMouseLocation: CGPoint?
    private var toastTask: Task<Void, Never>?
    public var dragDropState: MBDragDropState?
    public var dragDropSourceName: String?
    public var dragDropFileSummary: String?
    public var dragDropProgress: Double?

    private var compatibilityService: MWBCompatibilityService?
    private var mwbIdToUuid: [Int32: UUID] = [:]
    private var uuidToMwbId: [UUID: Int32] = [:]

    init() {
        // Pull persisted compatibility key instead of overwriting it with a placeholder.
        self.securityKey = self.compatibilitySettings.securityKey
        self.startAdvertising()
        self.startBrowsing()
        self.startSubnetScanning()
        self.configureCompatibility()
        self.setupPasteboardMonitoring()
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
            let id = self.uuid(for: peer.id)
            if !self.connectedMachines.contains(where: { $0.id == id }) {
                let machine = ConnectedMachine(
                    id: id, name: peer.name,
                    connection: NWConnection(
                        to: .hostPort(host: .ipv4(.any), port: 15101), using: .tcp))
                self.connectedMachines.append(machine)
            }
            self.showToast(message: "已连接 \(peer.name)", systemImage: "link")
        }
        service.onDisconnected = { [weak self] peer in
            guard let self else { return }
            let id = self.uuid(for: peer.id)
            self.connectedMachines.removeAll { $0.id == id }
            if self.activeMachineId == id {
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

    private func uuid(for id: Int32) -> UUID {
        if let existing = mwbIdToUuid[id] {
            return existing
        }
        let newId = UUID()
        self.mwbIdToUuid[id] = newId
        self.uuidToMwbId[newId] = id
        return newId
    }

    private func mwbId(for name: String) -> Int32? {
        guard let machine = connectedMachines.first(where: { $0.name.uppercased() == name }) else {
            return nil
        }
        return self.uuidToMwbId[machine.id]
    }

    public func requestSwitch(to machineId: UUID, reason: SwitchReason = .manual) {
        if self.protocolMode == .modern {
            // Native Switching
            self.activeMachineId = machineId
            return
        }

        guard let mwbId = uuidToMwbId[machineId] else { return }
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
        let screen = NSScreen.screens.first(where: { $0.frame.contains(edgeLocation) }) ?? mainScreen
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
        let screen = NSScreen.screens.first(where: { $0.frame.contains(edgeLocation) }) ?? mainScreen
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

    // MARK: - Hosting (Server)

    func startAdvertising() {
        do {
            let listener = try NWListener(using: .tcp)
            self.listener = listener

            listener.service = NWListener.Service(name: self.localName, type: self.serviceType)

            listener.newConnectionHandler = { [weak self] connection in
                MBLogger.network.info(
                    "New connection received from \(String(describing: connection.endpoint))")
                Task {
                    await self?.handleNewConnection(connection)
                }
            }

            listener.stateUpdateHandler = { newState in
                MBLogger.network.info("Listener state: \(String(describing: newState))")
            }

            listener.start(queue: .main)
        } catch {
            MBLogger.network.error("Failed to create listener: \(error.localizedDescription)")
        }
    }

    // MARK: - Browsing (Client Discovery)

    func startBrowsing() {
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Keep manual/scanned peers, replace bonjour ones
                let otherPeers = self.discoveredPeers.filter { $0.type != .bonjour }

                let bonjourPeers = results.compactMap { result -> DiscoveredPeer? in
                    if case .service(let name, _, _, _) = result.endpoint {
                        if name == self.localName { return nil }
                        return DiscoveredPeer(name: name, endpoint: result.endpoint, type: .bonjour)
                    }
                    return nil
                }

                self.discoveredPeers = otherPeers + bonjourPeers
                // Legacy support (optional)
                self.availablePeers = Array(results)
            }
        }

        browser.start(queue: .main)
    }

    public func connect(to result: NWBrowser.Result) {
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        self.handleNewConnection(connection)
    }

    public func connect(to endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        self.handleNewConnection(connection)
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

        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let host = NWEndpoint.Host(ip)
        self.showToast(message: "正在连接 \(ip)", systemImage: "arrow.right.circle")
        let connection = NWConnection(to: .hostPort(host: host, port: nwPort), using: .tcp)
        self.handleNewConnection(connection)
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

    // MARK: - Subnet Scanning

    public func startSubnetScanning() {
        print("Starting Subnet Scan...")
        let prefixes = self.getLocalIPPrefixes()
        guard !prefixes.isEmpty else {
            print("No local IP found for scanning.")
            return
        }

        // Scan typical /24 subnets for found local IPs
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.magicborder.scanner", attributes: .concurrent)

        for prefix in prefixes {
            print("Scanning subnet: \(prefix).1-254")
            for i in 1 ... 254 {
                let ip = "\(prefix).\(i)"
                queue.async(group: group) {
                    self.probe(ip: ip)
                }
            }
        }
    }

    private func getLocalIPPrefixes() -> [String] {
        // Simple heuristic: Get all IPv4 addresses, take first 3 octets
        let addresses = Host.current().addresses
        let ipv4s = addresses.filter { $0.contains(".") && !$0.starts(with: "127.") }
        let prefixes = ipv4s.compactMap { ip -> String? in
            let components = ip.split(separator: ".")
            if components.count == 4 {
                return components.prefix(3).joined(separator: ".")
            }
            return nil
        }
        return Array(Set(prefixes)) // Unique
    }

    private nonisolated func probe(ip: String) {
        let host = NWEndpoint.Host(ip)
        let port = NWEndpoint.Port(integerLiteral: 15101) // MWB Data Port

        let connection = NWConnection(to: .hostPort(host: host, port: port), using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Found Open Port at \(ip)!")
                Task { @MainActor [weak self] in
                    self?.addScannedPeer(ip: ip)
                }
                connection.cancel()
            default:
                break
            }
        }

        // Timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if connection.state != .ready {
                connection.cancel()
            }
        }

        connection.start(queue: .global())
    }

    private func addScannedPeer(ip: String) {
        // Deduplicate
        if !self.discoveredPeers.contains(where: { peer in
            if case .hostPort(let h, _) = peer.endpoint, case .ipv4(let ipv4) = h {
                return String(describing: ipv4) == ip
            }
            return false
        }) {
            // MWB Windows name resolution requires separate handshake or DNS lookup
            // For now, use IP as name or "PC (IP)"
            // Try reverse DNS? Dns.GetHostEntry equivalent?
            // Host.current().name(for: ip) might block.
            let name = "PC (\(ip))"
            let peer = DiscoveredPeer(
                name: name, endpoint: .hostPort(host: .init(ip), port: 15101), type: .scanned)
            self.discoveredPeers.append(peer)
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        self.peers.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                MBLogger.network.info(
                    "Connection ready: \(String(describing: connection.endpoint))")
                Task {
                    await self?.sendHandshake(connection: connection)
                    await self?.receiveLoop(connection: connection)
                }
            case .failed(let error):
                MBLogger.network.error("Connection failed: \(error.localizedDescription)")
                Task {
                    await self?.removeConnection(connection)
                }
            case .cancelled:
                Task {
                    await self?.removeConnection(connection)
                }
            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    private func removeConnection(_ connection: NWConnection) {
        if let index = peers.firstIndex(where: { $0 === connection }) {
            self.peers.remove(at: index)
        }
        if let index = connectedMachines.firstIndex(where: { $0.connection === connection }) {
            self.connectedMachines.remove(at: index)
        }
    }

    public func disconnect(machineId: UUID) {
        guard let machine = connectedMachines.first(where: { $0.id == machineId }) else { return }
        machine.connection.cancel()
        self.removeConnection(machine.connection)
        if self.activeMachineId == machineId {
            self.activeMachineId = nil
        }
    }

    public func reconnect(machineId: UUID) {
        guard let machine = connectedMachines.first(where: { $0.id == machineId }) else { return }
        let endpoint = machine.connection.endpoint
        machine.connection.cancel()
        self.removeConnection(machine.connection)
        let connection = NWConnection(to: endpoint, using: .tcp)
        self.handleNewConnection(connection)
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
        case .dual:
            if let remoteEvent = MBInputManager.shared.convertToRemoteEvent(snapshot: snapshot) {
                self.sendRemoteEvent(remoteEvent)
            }
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
        guard let activeId = activeMachineId else { return nil }
        return self.connectedMachines.first(where: { $0.id == activeId })?.connection
    }

    private func sendCompatibilityInput(event: CGEvent, type: CGEventType) {
        let snapshot = EventSnapshot(from: event, type: type)
        self.sendCompatibilityInput(snapshot: snapshot)
    }

    private func sendCompatibilityInput(snapshot: EventSnapshot) {
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
                self.compatibilityService?.sendKeyEvent(keyCode: key, flags: 0)
            }
        case .keyUp:
            if let key = MBInputManager.shared.windowsKeyCode(for: CGKeyCode(snapshot.keyCode)) {
                self.compatibilityService?.sendKeyEvent(keyCode: key, flags: 0x80)
            }
        case .flagsChanged:
            let macKey = CGKeyCode(snapshot.keyCode)
            guard let key = MBInputManager.shared.windowsKeyCode(for: macKey) else { break }
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
                        print("Send error: \(error)")
                    }
                })
        } catch {
            print("Encoding error: \(error)")
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
                print("Receive error: \(error)")
                return
            }

            if isComplete {
                print("Connection closed by peer")
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
                    let machine = ConnectedMachine(
                        id: info.id, name: info.name, connection: connection)
                    self.connectedMachines.append(machine)
                }
            case .inputEvent(let event):
                // Handle remote input
                MBInputManager.shared.simulateRemoteEvent(event)
            case .clipboardData(let payload):
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
            default:
                break
            }
        } catch {
            MBLogger.network.error("Decoding error: \(error.localizedDescription)")
        }
    }
}
