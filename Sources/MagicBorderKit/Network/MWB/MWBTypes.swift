public import Foundation

/// Selects which wire protocol the network stack uses.
/// Use `.mwbCompatibility` to interoperate with Windows Mouse Without Borders.
/// Use `.modern` for Mac-to-Mac connections using the native JSON/Bonjour protocol.
public enum MBProtocolMode: String, CaseIterable, Codable, Sendable {
    case modern
    case mwbCompatibility
}

public struct MWBPeer: Equatable, Hashable, Sendable {
    public let id: Int32
    public let name: String

    public init(id: Int32, name: String) {
        self.id = id
        self.name = name
    }
}

public struct MWBMouseEvent: Equatable, Sendable {
    public let x: Int32
    public let y: Int32
    public let wheel: Int32
    public let flags: Int32

    public init(x: Int32, y: Int32, wheel: Int32, flags: Int32) {
        self.x = x
        self.y = y
        self.wheel = wheel
        self.flags = flags
    }
}

public struct MWBKeyEvent: Equatable, Sendable {
    public let keyCode: Int32
    public let flags: Int32

    public init(keyCode: Int32, flags: Int32) {
        self.keyCode = keyCode
        self.flags = flags
    }
}

public enum MWBSessionKind: Sendable {
    case message
    case clipboard
}

public enum MWBCompatibilityEvent: Sendable {
    case connected(MWBPeer)
    case disconnected(MWBPeer)
    case remoteMouse(MWBMouseEvent)
    case remoteKey(MWBKeyEvent)
    case machineSwitched(MWBPeer?)
    case machineMatrix([String])
    case matrixOptionsUpdated(twoRow: Bool, swap: Bool)
    case clipboardText(String)
    case clipboardImage(Data)
    case clipboardFiles([URL])
    case hideMouse
    case dragDropOperation(String?)
    case dragDropBegin(String?)
    case dragDropEnd
    case captureScreen(Int32?)
    case reconnectAttempt(String)
    case reconnectStopped(String)
    case log(String)
    case error(String)
}

@MainActor
public protocol MWBCompatibilityServicing: AnyObject {
    var events: AsyncStream<MWBCompatibilityEvent> { get }
    func start(securityKey: String)
    func stop()
    func updateSecurityKey(_ key: String)
    func updatePorts(messagePort: UInt16, clipboardPort: UInt16)
    func connectToHost(ip: String, messagePort: UInt16?, clipboardPort: UInt16?)
    func disconnect(peerId: Int32)
    func reconnect(peerId: Int32)
    func sendMachineMatrix(_ machines: [String], twoRow: Bool, swap: Bool)
    func sendNextMachine(targetId: Int32?)
    func stopAutoReconnect()
    func sendMouseEvent(x: Int32, y: Int32, wheel: Int32, flags: Int32)
    func sendKeyEvent(keyCode: Int32, flags: Int32)
    func sendHideMouse()
    func sendClipboardText(_ text: String)
    func sendClipboardImage(_ data: Data)
    func sendClipboardImage(_ data: Data, to peerId: Int32?)
    func sendFileDrop(_ urls: [URL])
}
