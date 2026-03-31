import Foundation
import Network

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
    case reconnectAttempt(String)
    case reconnectStopped(String)
    case log(String)
    case error(String)
}

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

    func activate(machine: Machine?)
    func centerRemoteCursor()

    func sendRemoteInput(snapshot: EventSnapshot, activeMachineId: UUID?)
    func sendClipboardText(_ text: String, activeMachineId: UUID?)
    func sendClipboardImage(_ data: Data, activeMachineId: UUID?)
    func sendScreenCapture(_ data: Data, to peerID: Int32?)
    func sendMachineMatrix(names: [String], twoRow: Bool, swap: Bool)
    func sendFileDrop(_ urls: [URL])
}
