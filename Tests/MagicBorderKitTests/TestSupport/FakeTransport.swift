import Foundation
@testable import MagicBorderKit
import Network

@MainActor
final class FakeTransport: MBTransport {
    enum Call: Equatable {
        case start
        case stop
        case updateConfiguration(securityKey: String, messagePort: UInt16, clipboardPort: UInt16)
        case connectEndpoint(String)
        case connectHost(String, UInt16)
        case disconnect(UUID)
        case reconnect(UUID)
        case activate(UUID?)
        case centerRemoteCursor
        case remoteInput(UUID?)
        case clipboardText(String, UUID?)
        case clipboardImage(Int, UUID?)
        case screenCapture(Int, Int32?)
        case matrix([String], Bool, Bool)
        case fileDrop([URL])
    }

    private let continuation: AsyncStream<MBTransportEvent>.Continuation
    private(set) var calls: [Call] = []
    let events: AsyncStream<MBTransportEvent>

    init() {
        let stream = AsyncStream.makeStream(of: MBTransportEvent.self)
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    func emit(_ event: MBTransportEvent) {
        self.continuation.yield(event)
    }

    func start() {
        self.calls.append(.start)
    }

    func stop() {
        self.calls.append(.stop)
    }

    func updateConfiguration(securityKey: String, settings: MBCompatibilitySettings) {
        self.calls.append(
            .updateConfiguration(
                securityKey: securityKey,
                messagePort: settings.messagePort,
                clipboardPort: settings.clipboardPort))
    }

    func connect(to endpoint: NWEndpoint) {
        self.calls.append(.connectEndpoint("\(endpoint)"))
    }

    func connect(to result: NWBrowser.Result) {
        self.connect(to: result.endpoint)
    }

    func connectToHost(ip: String, port: UInt16) {
        self.calls.append(.connectHost(ip, port))
    }

    func disconnect(machine: Machine) {
        self.calls.append(.disconnect(machine.id))
    }

    func reconnect(machine: Machine) {
        self.calls.append(.reconnect(machine.id))
    }

    func activate(machine: Machine?) {
        self.calls.append(.activate(machine?.id))
    }

    func centerRemoteCursor() {
        self.calls.append(.centerRemoteCursor)
    }

    func sendRemoteInput(snapshot _: EventSnapshot, activeMachineId: UUID?) {
        self.calls.append(.remoteInput(activeMachineId))
    }

    func sendClipboardText(_ text: String, activeMachineId: UUID?) {
        self.calls.append(.clipboardText(text, activeMachineId))
    }

    func sendClipboardImage(_ data: Data, activeMachineId: UUID?) {
        self.calls.append(.clipboardImage(data.count, activeMachineId))
    }

    func sendScreenCapture(_ data: Data, to peerID: Int32?) {
        self.calls.append(.screenCapture(data.count, peerID))
    }

    func sendMachineMatrix(names: [String], twoRow: Bool, swap: Bool) {
        self.calls.append(.matrix(names, twoRow, swap))
    }

    func sendFileDrop(_ urls: [URL]) {
        self.calls.append(.fileDrop(urls))
    }
}
