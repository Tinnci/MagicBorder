public import Foundation
public import Network
private import OSLog
public import Observation

@MainActor
@Observable
public final class MBNetworkManager: Observation.Observable {
    public static let localMachineUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()

    public typealias SwitchState = MBSessionCoordinator.SwitchState
    public typealias SwitchReason = MBSessionCoordinator.SwitchReason

    private struct AppliedConfiguration: Equatable {
        let protocolMode: MBProtocolMode
        let securityKey: String
        let messagePort: UInt16
        let clipboardPort: UInt16
        let modifierRemapMode: MBModifierRemapMode
        let invertRemoteScroll: Bool
        let remoteScrollSpeed: Double
    }

    public let port: NWEndpoint.Port = 12345
    public let serviceType = "_magicborder._tcp"

    public var connectedMachines: [Machine] = []
    public var discoveredPeers: [DiscoveredPeer] = []

    public let localID: UUID
    public let localName: String
    public let localNumericID: Int32
    public var localDisplayName: String { self.localName }

    public let inputManager: MBInputManager
    public let sessionCoordinator: MBSessionCoordinator
    public let clipboardBridge: MBClipboardBridge

    public var switchState: SwitchState { self.sessionCoordinator.switchState }
    public var activeMachineId: UUID? {
        get { self.sessionCoordinator.activeMachineId }
        set { self.sessionCoordinator.setActiveMachine(newValue) }
    }

    public var activeMachineName: String { self.sessionCoordinator.activeMachineName }
    public var lastSwitchTimestamp: Date? { self.sessionCoordinator.lastSwitchTimestamp }
    public var toast: MBToastEvent?

    public var protocolMode: MBProtocolMode = .mwbCompatibility
    public var securityKey: String = ""
    public var compatibilitySettings: MBCompatibilitySettings
    public let savedHosts: MBSavedHostStore

    public var isConnectingHost: String?
    public var pairingDebugLog: [String] = []
    public var pairingError: String?

    /// Spatial arrangement of machines in the grid.
    public var arrangement: MachineArrangement = .init()

    var discoveryService: MBDiscoveryService?
    private let discoveryEventsTask = CancellableTaskSlot()
    private let modernEventsTask = CancellableTaskSlot()
    private let compatibilityEventsTask = CancellableTaskSlot()
    private let toastTask = CancellableTaskSlot()
    private let connectingTimeoutTask = CancellableTaskSlot()
    private var lastAppliedConfiguration: AppliedConfiguration?
    private var pendingManualHost: String?

    private let modernTransport: any MBTransport
    private let compatibilityTransport: any MBTransport
    private let screenCapturer: any ScreenCapturing
    private let cursorController: any CursorControlling

    private var currentTransport: any MBTransport {
        self.protocolMode == .modern ? self.modernTransport : self.compatibilityTransport
    }

    public convenience init(
        inputManager: MBInputManager = MBInputManager(),
        compatibilitySettings: MBCompatibilitySettings = MBCompatibilitySettings()
    ) {
        self.init(
            localName: Host.current().localizedName ?? "Unknown Mac",
            localID: UUID(),
            localNumericID: .random(in: 1000...999999),
            compatibilitySettings: compatibilitySettings,
            inputManager: inputManager,
            startDiscovery: true,
            startTransports: true,
            startClipboardMonitoring: true)
    }

    public init(
        localName: String,
        localID: UUID,
        localNumericID: Int32,
        compatibilitySettings settings: MBCompatibilitySettings,
        inputManager: MBInputManager,
        modernTransport: (any MBTransport)? = nil,
        compatibilityTransport: (any MBTransport)? = nil,
        pasteboard: any PasteboardAccessing = SystemPasteboard(),
        screenGeometry: any ScreenGeometryProviding = SystemScreenGeometryProvider(),
        clock: any ClockProviding = SystemClock(),
        cursorController: any CursorControlling = SystemCursorController(),
        screenCapturer: any ScreenCapturing = CGScreenCapturer(),
        savedHosts: MBSavedHostStore? = nil,
        isFrontmostAppFullscreen: @escaping () -> Bool = { false },
        startDiscovery: Bool,
        startTransports: Bool,
        startClipboardMonitoring: Bool
    ) {
        self.localName = localName
        self.localID = localID
        self.localNumericID = localNumericID
        self.compatibilitySettings = settings
        self.protocolMode = settings.protocolMode
        self.securityKey = settings.securityKey
        self.savedHosts = savedHosts ?? MBSavedHostStore()
        self.inputManager = inputManager
        self.screenCapturer = screenCapturer
        self.cursorController = cursorController

        let resolvedModern =
            modernTransport
            ?? MBModernTransport(
                serviceType: self.serviceType,
                localName: localName,
                localID: localID,
                securityKey: settings.securityKey,
                port: self.port,
                screenGeometry: screenGeometry)
        let resolvedCompatibility =
            compatibilityTransport
            ?? MBMWBTransport(
                localName: localName,
                localID: localNumericID,
                settings: settings,
                screenGeometry: screenGeometry,
                clock: clock)

        self.modernTransport = resolvedModern
        self.compatibilityTransport = resolvedCompatibility

        // Placeholder closures replaced after `self` initialization via weak capture.
        var coordinatorBox: (() -> MBNetworkManager?) = { nil }

        let coordinatorDeps = MBSessionCoordinator.Dependencies(
            connectedMachines: { coordinatorBox()?.connectedMachines ?? [] },
            arrangement: { coordinatorBox()?.arrangement ?? .init() },
            settings: { coordinatorBox()?.compatibilitySettings ?? settings },
            updateRemoteTarget: { target in inputManager.setRemoteTarget(target) },
            emitToast: { event in coordinatorBox()?.showToast(event) },
            appendLog: { message in coordinatorBox()?.appendPairingLog(message) },
            activateRemoteMachine: { machine in
                guard let owner = coordinatorBox(),
                    let remoteTransport = owner.currentTransport as? any MBRemoteActivationTransport
                else { return false }
                remoteTransport.activate(machine: machine)
                return true
            },
            centerRemoteCursor: {
                guard let owner = coordinatorBox(),
                    let remoteTransport = owner.currentTransport as? any MBRemoteActivationTransport
                else { return }
                remoteTransport.centerRemoteCursor()
            },
            isFrontmostAppFullscreen: isFrontmostAppFullscreen)

        self.sessionCoordinator = MBSessionCoordinator(
            localMachineID: MBNetworkManager.localMachineUUID,
            localMachineName: localName,
            dependencies: coordinatorDeps,
            screenGeometry: screenGeometry,
            clock: clock,
            cursorController: cursorController)

        self.clipboardBridge = MBClipboardBridge(
            pasteboard: pasteboard,
            ignoreNextLocalChange: { inputManager.ignoreNextClipboardChange() },
            emitToast: { event in coordinatorBox()?.showToast(event) },
            sendClipboardText: { text in coordinatorBox()?.sendClipboardText(text) },
            sendClipboardImage: { data in coordinatorBox()?.sendClipboardImage(data) },
            sendFileDrop: { urls in coordinatorBox()?.sendFileDrop(urls) })

        coordinatorBox = { [weak self] in self }

        inputManager.routingDelegate = self
        inputManager.syncTapConfiguration(wrapCursor: settings.wrapCursor)

        if startDiscovery {
            let service = MBDiscoveryService(serviceType: self.serviceType, localName: localName)
            self.discoveryService = service
            service.startBrowsing()
            service.startSubnetScanning()
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.consumeDiscoveryEvents(service)
            }
            self.discoveryEventsTask.replace(with: task)
        }

        if startTransports {
            self.modernTransport.start()
            self.compatibilityTransport.start()
        }

        let modernTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.consumeTransportEvents(resolvedModern)
        }
        self.modernEventsTask.replace(with: modernTask)

        let compatTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.consumeTransportEvents(resolvedCompatibility)
        }
        self.compatibilityEventsTask.replace(with: compatTask)

        self.applyCompatibilitySettings()

        if startClipboardMonitoring {
            inputManager.startClipboardSync()
        }
    }

    deinit {
        self.discoveryEventsTask.cancel()
        self.modernEventsTask.cancel()
        self.compatibilityEventsTask.cancel()
        self.toastTask.cancel()
        self.connectingTimeoutTask.cancel()
    }

    static func testing(
        localName: String = "Test Mac",
        compatibilitySettings: MBCompatibilitySettings,
        inputManager: MBInputManager,
        modernTransport: (any MBTransport)? = nil,
        compatibilityTransport: (any MBTransport)? = nil,
        pasteboard: any PasteboardAccessing,
        screenGeometry: any ScreenGeometryProviding,
        clock: any ClockProviding,
        cursorController: any CursorControlling,
        screenCapturer: any ScreenCapturing
    ) -> MBNetworkManager {
        let suiteName = "MagicBorderTests.hosts.\(UUID().uuidString)"
        let hostDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        return MBNetworkManager(
            localName: localName,
            localID: UUID(),
            localNumericID: 1234,
            compatibilitySettings: compatibilitySettings,
            inputManager: inputManager,
            modernTransport: modernTransport,
            compatibilityTransport: compatibilityTransport,
            pasteboard: pasteboard,
            screenGeometry: screenGeometry,
            clock: clock,
            cursorController: cursorController,
            screenCapturer: screenCapturer,
            savedHosts: MBSavedHostStore(defaults: hostDefaults),
            startDiscovery: false,
            startTransports: false,
            startClipboardMonitoring: false)
    }

    // MARK: - Event Streams

    private func consumeDiscoveryEvents(_ service: MBDiscoveryService) async {
        for await _ in service.events {
            self.discoveredPeers = service.discoveredPeers
        }
    }

    private func consumeTransportEvents(_ transport: any MBTransport) async {
        for await event in transport.events {
            if self.clipboardBridge.handleTransportEvent(event, settings: self.compatibilitySettings) {
                continue
            }
            self.handleNonClipboardEvent(event)
        }
    }

    private func handleNonClipboardEvent(_ event: MBTransportEvent) {
        switch event {
        case .machineConnected(let machine):
            self.connectingTimeoutTask.cancel()
            self.isConnectingHost = nil
            if let host = self.pendingManualHost {
                self.pendingManualHost = nil
                self.savedHosts.recordConnection(
                    address: host,
                    name: machine.name,
                    protocolMode: self.protocolMode,
                    messagePort: self.compatibilitySettings.messagePort,
                    clipboardPort: self.compatibilitySettings.clipboardPort)
            }
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
                self.showToast(.disconnected(disconnected.name))
            }
        case .activeMachineChanged(let id, let name):
            self.sessionCoordinator.handleTransportActiveMachineChanged(id: id, name: name)
        case .arrangementReceived(let matrix):
            self.updateLocalMatrix(names: matrix)
        case .arrangementOptionsUpdated(let twoRow, let swap):
            self.compatibilitySettings.matrixOneRow = !twoRow
            self.compatibilitySettings.matrixCircle = swap
        case .remoteEvent(let remoteEvent):
            self.inputManager.simulateRemoteEvent(remoteEvent)
        case .mwbMouse(let mouseEvent):
            self.inputManager.simulateMouseEvent(mouseEvent)
        case .mwbKey(let keyEvent):
            self.inputManager.simulateKeyEvent(keyEvent)
        case .clipboardText, .clipboardImage, .clipboardFiles, .dragDropStateChanged:
            break
        case .hideMouse:
            self.cursorController.hide()
        case .screenCaptureRequested(let sourceID):
            self.sendScreenCapture(to: sourceID)
        case .reconnectAttempt(let host):
            self.showToast(.reconnecting(host))
        case .reconnectStopped(let host):
            self.showToast(.reconnectStopped(host))
        case .log(let message):
            self.appendPairingLog(message)
        case .error(let message):
            self.connectingTimeoutTask.cancel()
            self.isConnectingHost = nil
            self.setPairingError(message)
        }
    }

    // MARK: - Diagnostics & Toasts

    public func appendPairingLog(_ message: String) {
        let timestamp = Date.now.formatted(.iso8601)
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

    public func showToast(_ event: MBToastEvent, duration: Duration = .milliseconds(2600)) {
        self.toast = event
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.toast = nil
        }
        self.toastTask.replace(with: task)
    }

    // MARK: - Routing & Switching

    public func handleLocalPasteboard(_ content: MBPasteboardContent) {
        self.clipboardBridge.handleLocalPasteboard(content, settings: self.compatibilitySettings)
    }

    private func sendScreenCapture(to sourceId: Int32?) {
        guard let image = self.screenCapturer.captureMainScreenPNG(),
            let remoteTransport = self.compatibilityTransport as? any MBRemoteActivationTransport
        else { return }
        remoteTransport.sendScreenCapture(image, to: sourceId)
    }

    public func requestSwitch(to machineId: UUID, reason: SwitchReason = .manual) {
        self.sessionCoordinator.requestSwitch(to: machineId, reason: reason)
    }

    public func requestSwitch(toMachineNamed name: String, reason: SwitchReason = .manual) {
        self.sessionCoordinator.requestSwitch(toMachineNamed: name, reason: reason)
    }

    public func forceReturnToLocal(reason: String) {
        self.sessionCoordinator.forceReturnToLocal(reason: reason)
    }

    public func sendMachineMatrix(names: [String], twoRow: Bool = false, swap: Bool = false) {
        let uppercased = names.map { $0.uppercased() }
        self.updateLocalMatrix(names: uppercased)
        if let matrixTransport = self.currentTransport as? any MBMatrixSyncTransport {
            matrixTransport.sendMachineMatrix(names: uppercased, twoRow: twoRow, swap: swap)
        }
    }

    public func syncArrangement(machineIDs: [UUID], twoRow: Bool, swap: Bool) {
        self.updateArrangement(machineIDs: machineIDs)
        let names = self.visibleMachines().map { $0.name.uppercased() }
        if let matrixTransport = self.currentTransport as? any MBMatrixSyncTransport {
            matrixTransport.sendMachineMatrix(names: names, twoRow: twoRow, swap: swap)
        }
    }

    @discardableResult
    public func sendFileDrop(_ urls: [URL]) -> Bool {
        guard self.compatibilitySettings.transferFiles else {
            self.showToast(.fileTransferDisabled)
            return false
        }
        guard !urls.isEmpty, let fileTransport = self.currentTransport as? any MBFileDropTransport else {
            return false
        }
        fileTransport.sendFileDrop(urls)
        return true
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

    public func handleLocalMouseEvent(snapshot: EventSnapshot) {
        self.sessionCoordinator.handleLocalMouseEvent(snapshot: snapshot)
    }

    public func handleRemoteMouseEvent(snapshot: EventSnapshot) {
        self.sessionCoordinator.handleRemoteMouseEvent(snapshot: snapshot)
    }

    // MARK: - Connection & Configuration

    public func connect(to result: NWBrowser.Result) {
        self.currentTransport.connect(to: result)
    }

    public func connect(to endpoint: NWEndpoint) {
        self.currentTransport.connect(to: endpoint)
    }

    public func connectToHost(ip: String, port: UInt16? = nil) {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resolvedPort =
            port
            ?? {
                switch self.protocolMode {
                case .modern:
                    self.port.rawValue
                case .mwbCompatibility:
                    self.compatibilitySettings.messagePort
                }
            }()
        self.pendingManualHost = trimmed
        self.isConnectingHost = trimmed
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self else { return }
            if self.isConnectingHost == trimmed {
                self.isConnectingHost = nil
            }
        }
        self.connectingTimeoutTask.replace(with: timeoutTask)
        self.showToast(.connecting(trimmed))
        self.currentTransport.connectToHost(ip: trimmed, port: resolvedPort)
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
        self.inputManager.syncTapConfiguration(
            MBTapConfiguration(
                wrapCursor: self.compatibilitySettings.wrapCursor,
                escapeMode: self.compatibilitySettings.escapeMode,
                globalHotkeysEnabled: self.compatibilitySettings.globalHotkeysEnabled))
        self.inputManager.setIgnoreConcealedClipboard(
            self.compatibilitySettings.ignoreConcealedClipboard)

        let nextConfig = AppliedConfiguration(
            protocolMode: self.compatibilitySettings.protocolMode,
            securityKey: self.compatibilitySettings.securityKey,
            messagePort: self.compatibilitySettings.messagePort,
            clipboardPort: self.compatibilitySettings.clipboardPort,
            modifierRemapMode: self.compatibilitySettings.modifierRemapMode,
            invertRemoteScroll: self.compatibilitySettings.invertRemoteScroll,
            remoteScrollSpeed: self.compatibilitySettings.remoteScrollSpeed)
        guard nextConfig != self.lastAppliedConfiguration else { return }
        self.lastAppliedConfiguration = nextConfig

        self.protocolMode = nextConfig.protocolMode
        self.securityKey = nextConfig.securityKey
        self.currentTransport.updateConfiguration(
            securityKey: nextConfig.securityKey,
            settings: self.compatibilitySettings)
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
