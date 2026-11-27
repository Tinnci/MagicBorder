public import Foundation
public import Network

@MainActor
public enum MBTransportEvent: Sendable {
    case machineConnected(Machine)
    case machineDisconnected(UUID)
    case activeMachineChanged(UUID?, String?)
    case arrangementReceived([String])
    case arrangementOptionsUpdated(twoRow: Bool, swap: Bool)
    case remoteEvent(RemoteEvent)
    case mwbMouse(MWBMouseEvent)
    case mwbKey(MWBKeyEvent)
    case clipboardText(String)
    case clipboardImage(Data)
    case clipboardFiles([URL])
    case dragDropStateChanged(MBDragDropState?, sourceName: String?)
    case hideMouse
    case screenCaptureRequested(Int32?)
    case peerTelemetryUpdated(UUID, PeerTelemetry)
    case reconnectAttempt(String)
    case reconnectStopped(String)
    case log(String)
    case error(String)
}

/// Core transport capabilities supported by both Modern and MWB compatibility transports.
@MainActor
public protocol MBTransport: AnyObject {
    var events: AsyncStream<MBTransportEvent> { get }

    func start()
    func stop()
    func updateConfiguration(securityKey: String, settings: MBCompatibilitySettings)

    func connect(to endpoint: NWEndpoint)
    func connect(to result: NWBrowser.Result)
    func connectToHost(ip: String, port: UInt16)
    func disconnect(machine: Machine)
    func reconnect(machine: Machine)

    func sendRemoteInput(snapshot: EventSnapshot, activeMachineId: UUID?)
    func sendClipboardText(_ text: String, activeMachineId: UUID?)
    func sendClipboardImage(_ data: Data, activeMachineId: UUID?)
}

/// Optional capability for transports that synchronize machine matrix layout across peers.
@MainActor
public protocol MBMatrixSyncTransport: MBTransport {
    func sendMachineMatrix(names: [String], twoRow: Bool, swap: Bool)
}

/// Optional capability for transports that support cross-machine file drops.
@MainActor
public protocol MBFileDropTransport: MBTransport {
    func sendFileDrop(_ urls: [URL])
}

/// Optional capability for transports where the peer coordinates active machine switching and cursor centering.
@MainActor
public protocol MBRemoteActivationTransport: MBTransport {
    func activate(machine: Machine?)
    func centerRemoteCursor()
    func sendLockScreen()
    func sendScreenCapture(_ data: Data, to peerID: Int32?)
}
