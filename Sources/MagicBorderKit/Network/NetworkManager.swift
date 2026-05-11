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

    public typealias SwitchState = MBSessionCoordinator.SwitchState
    public typealias SwitchReason = MBSessionCoordinator.SwitchReason

    // Config
    let port: NWEndpoint.Port = 12345
    let serviceType = "_magicborder._tcp"

    public var connectedMachines: [Machine] = []

    // MARK: - Discovery (delegated to MBDiscoveryService)

    private var discoveryService: MBDiscoveryService?

    /// Mirror of `MBDiscoveryService.discoveredPeers` — kept as observable for the UI.
    public var discoveredPeers: [DiscoveredPeer] = []

    // Identity
    let localID: UUID
    let localName: String
    let localNumericID: Int32
    public var localDisplayName: String { self.localName }

    public private(set) var sessionCoordinator: MBSessionCoordinator!
    public var switchState: SwitchState { self.sessionCoordinator.switchState }
    public var activeMachineId: UUID? {
        get { self.sessionCoordinator.activeMachineId }
        set { self.sessionCoordinator.setActiveMachine(newValue) }
    }

    public var activeMachineName: String { self.sessionCoordinator.activeMachineName }
    public var lastSwitchTimestamp: Date? { self.sessionCoordinator.lastSwitchTimestamp }
    public var toast: MBToastState?

    public var protocolMode: MBProtocolMode = .mwbCompatibility
    public var securityKey: String = "" {
        didSet {
            self.currentTransportIfAvailable?.updateConfiguration(
                securityKey: self.securityKey,
                settings: self.compatibilitySettings)
        }
    }

    public var compatibilitySettings = MBCompatibilitySettings()

    public var pairingDebugLog: [String] = []
    public var pairingError: String?

    /// Spatial arrangement of machines in the grid.
    public var arrangement: MachineArrangement = .init()
    private var toastTask: Task<Void, Never>?
    public private(set) var clipboardBridge: MBClipboardBridge!

    private var modernTransport: (any MBTransport)!
    private var compatibilityTransport: (any MBTransport)!
    private var currentTransportIfAvailable: (any MBTransport)? {
        self.protocolMode == .modern ? self.modernTransport : self.compatibilityTransport
    }

    private var currentTransport: any MBTransport {
        self.protocolMode == .modern ? self.modernTransport : self.compatibilityTransport
    }

    convenience init() {
        self.init(
            localName: Host.current().localizedName ?? "Unknown Mac",
            localID: UUID(),
            localNumericID: .random(in: 1000 ... 999999),
            compatibilitySettings: MBCompatibilitySettings(),
            startDiscovery: true,
            startTransports: true,
            startClipboardMonitoring: true)
    }

    init(
        localName: String,
        localID: UUID,
        localNumericID: Int32,
        compatibilitySettings settings: MBCompatibilitySettings,
        modernTransport: (any MBTransport)? = nil,
        compatibilityTransport: (any MBTransport)? = nil,
        startDiscovery: Bool,
        startTransports: Bool,
        startClipboardMonitoring: Bool)
    {
        self.localName = localName
        self.localID = localID
        self.localNumericID = localNumericID
        self.compatibilitySettings = settings
        self.securityKey = ""
        self.connectedMachines = []
        self.discoveredPeers = []
        self.pairingDebugLog = []
        self.pairingError = nil
        self.arrangement = .init()

        self.modernTransport = modernTransport ?? MBModernTransport(
            serviceType: self.serviceType,
            localName: self.localName,
            localID: self.localID,
            securityKey: settings.securityKey)
        self.compatibilityTransport = compatibilityTransport ?? MBMWBTransport(
            localName: self.localName,
            localID: self.localNumericID,
            settings: settings)
        self.sessionCoordinator = MBSessionCoordinator(
            localMachineID: MBNetworkManager.localMachineUUID,
            localMachineName: self.localName,
            connectedMachinesProvider: { [weak self] in self?.connectedMachines ?? [] },
            arrangementProvider: { [weak self] in self?.arrangement ?? .init() },
            settingsProvider: { [weak self] in self?.compatibilitySettings ?? MBCompatibilitySettings() },
            protocolModeProvider: { [weak self] in self?.protocolMode ?? .mwbCompatibility },
            updateRemoteTarget: { target in MBInputManager.shared.setRemoteTarget(target) },
            showToast: { [weak self] message, systemImage in
                self?.showToast(message: message, systemImage: systemImage)
            },
            appendLog: { [weak self] message in self?.appendPairingLog(message) },
            activateCompatibilityMachine: { [weak self] machine in
                self?.compatibilityTransport.activate(machine: machine)
            },
            centerRemoteCursor: { [weak self] in self?.compatibilityTransport.centerRemoteCursor() })
        self.clipboardBridge = MBClipboardBridge(
            showToast: { [weak self] message, systemImage in
                self?.showToast(message: message, systemImage: systemImage)
            },
            sendClipboardText: { [weak self] text in self?.sendClipboardText(text) },
            sendClipboardImage: { [weak self] data in self?.sendClipboardImage(data) },
            sendFileDrop: { [weak self] urls in self?.sendFileDrop(urls) })

        // Pull persisted compatibility key instead of overwriting it with a placeholder.
        self.securityKey = settings.securityKey

        if startDiscovery {
            let svc = MBDiscoveryService(serviceType: serviceType, localName: localName)
            self.discoveryService = svc
            svc.startBrowsing()
            svc.startSubnetScanning()
            Task { @MainActor [weak self] in await self?.consumeDiscoveryEvents(svc) }
        }

        // Break circular dep: InputManager calls back through MBInputRoutingDelegate.
        MBInputManager.shared.routingDelegate = self

        if startTransports {
            self.modernTransport.start()
            self.compatibilityTransport.start()
        }
        Task { @MainActor [weak self] in await self?.consumeTransportEvents(self?.modernTransport) }
        Task { @MainActor [weak self] in await self?.consumeTransportEvents(self?.compatibilityTransport) }
        self.configureCompatibility()
        if startClipboardMonitoring {
            self.setupPasteboardMonitoring()
        }
    }

    static func testing(
        localName: String = "Test Mac",
        compatibilitySettings: MBCompatibilitySettings = MBCompatibilitySettings(),
        modernTransport: (any MBTransport)? = nil,
        compatibilityTransport: (any MBTransport)? = nil)
        -> MBNetworkManager
    {
        MBNetworkManager(
            localName: localName,
            localID: UUID(),
            localNumericID: 1234,
            compatibilitySettings: compatibilitySettings,
            modernTransport: modernTransport,
            compatibilityTransport: compatibilityTransport,
            startDiscovery: false,
            startTransports: false,
            startClipboardMonitoring: false)
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
            if self.clipboardBridge.handleTransportEvent(event, settings: self.compatibilitySettings) {
                continue
            }
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
                if self.sessionCoordinator.activeMachineId == id {
                    self.forceReturnToLocal(reason: "disconnect")
                }
                if let disconnected {
                    self.showToast(message: "已断开 \(disconnected.name)", systemImage: "link.slash")
                }
            case .activeMachineChanged(let id, let name):
                self.sessionCoordinator.handleTransportActiveMachineChanged(id: id, name: name)
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
            case .clipboardText, .clipboardImage, .clipboardFiles, .dragDropStateChanged:
                break
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
        self.clipboardBridge.handleLocalPasteboard(content, settings: self.compatibilitySettings)
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
        self.sessionCoordinator.requestSwitch(to: machineId, reason: reason)
    }

    public func forceReturnToLocal(reason: String) {
        self.sessionCoordinator.forceReturnToLocal(reason: reason)
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
        self.sessionCoordinator.requestSwitch(toMachineNamed: name, reason: reason)
    }

    public func sendMachineMatrix(names: [String], twoRow: Bool = false, swap: Bool = false) {
        let uppercased = names.map { $0.uppercased() }
        self.updateLocalMatrix(names: uppercased)
        self.currentTransport.sendMachineMatrix(names: uppercased, twoRow: twoRow, swap: swap)
    }

    public func syncArrangement(machineIDs: [UUID], twoRow: Bool, swap: Bool) {
        self.updateArrangement(machineIDs: machineIDs)
        let names = self.visibleMachines().map { $0.name.uppercased() }
        self.currentTransport.sendMachineMatrix(names: names, twoRow: twoRow, swap: swap)
    }

    @discardableResult
    public func sendFileDrop(_ urls: [URL]) -> Bool {
        guard self.compatibilitySettings.transferFiles else {
            self.showToast(message: "文件传输已关闭", systemImage: "nosign")
            return false
        }
        guard !urls.isEmpty else { return false }
        self.currentTransport.sendFileDrop(urls)
        return true
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

    public func visibleMachines() -> [Machine] {
        MachineListResolver.visibleMachines(
            localMachineID: MBNetworkManager.localMachineUUID,
            localMachineName: self.localName,
            connectedMachines: self.connectedMachines,
            arrangement: self.arrangement)
    }

    public func handleLocalMouseEvent(_ event: CGEvent, type: CGEventType) {
        let snapshot = EventSnapshot(from: event, type: type)
        self.handleLocalMouseEvent(snapshot: snapshot)
    }

    public func handleLocalMouseEvent(snapshot: EventSnapshot) {
        self.sessionCoordinator.handleLocalMouseEvent(snapshot: snapshot)
    }

    public func handleRemoteMouseEvent(snapshot: EventSnapshot) {
        self.sessionCoordinator.handleRemoteMouseEvent(snapshot: snapshot)
    }

    // MARK: - Connection Handling

    public func connect(to result: NWBrowser.Result) {
        self.currentTransport.connect(to: result)
    }

    public func connect(to endpoint: NWEndpoint) {
        self.currentTransport.connect(to: endpoint)
    }

    public func connectToHost(ip: String, port: UInt16? = nil) {
        guard !ip.isEmpty else { return }
        let resolvedPort = port ?? {
            switch self.protocolMode {
            case .modern:
                15101
            case .mwbCompatibility:
                self.compatibilitySettings.messagePort
            }
        }()
        self.showToast(message: "正在连接 \(ip)", systemImage: "arrow.right.circle")
        self.currentTransport.connectToHost(ip: ip, port: resolvedPort)
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
        self.currentTransport.sendRemoteInput(
            snapshot: snapshot,
            activeMachineId: self.sessionCoordinator.activeMachineId)
    }

    private func sendClipboardText(_ text: String) {
        self.currentTransport.sendClipboardText(
            text,
            activeMachineId: self.sessionCoordinator.activeMachineId)
    }

    private func sendClipboardImage(_ data: Data) {
        self.currentTransport.sendClipboardImage(
            data,
            activeMachineId: self.sessionCoordinator.activeMachineId)
    }
}

// MARK: - MBInputRoutingDelegate

extension MBNetworkManager: MBInputRoutingDelegate {}
