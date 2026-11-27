import CoreGraphics
import Foundation
import Network
import os

@testable import MagicBorderKit

@MainActor
final class FakeTransport:
    MBTransport,
    MBMatrixSyncTransport,
    MBFileDropTransport,
    MBRemoteActivationTransport
{
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

@MainActor
final class FakeMWBCompatibilityService: MWBCompatibilityServicing {
    let events: AsyncStream<MWBCompatibilityEvent>
    private let continuation: AsyncStream<MWBCompatibilityEvent>.Continuation

    private(set) var disconnectedPeerIDs: [Int32] = []
    private(set) var reconnectedPeerIDs: [Int32] = []
    private(set) var sentMouseEvents: [MWBMouseEvent] = []
    private(set) var sentKeyEvents: [MWBKeyEvent] = []
    private(set) var sentNextMachineTargets: [Int32?] = []
    private(set) var stopAutoReconnectCount = 0

    init() {
        let stream = AsyncStream.makeStream(of: MWBCompatibilityEvent.self)
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    func emit(_ event: MWBCompatibilityEvent) {
        self.continuation.yield(event)
    }

    func updateSecurityKey(_: String) {}
    func updatePorts(messagePort _: UInt16, clipboardPort _: UInt16) {}
    func start(securityKey _: String) {}
    func stop() {}
    func connectToHost(ip _: String, messagePort _: UInt16?, clipboardPort _: UInt16?) {}

    func disconnect(peerId: Int32) {
        self.disconnectedPeerIDs.append(peerId)
    }

    func reconnect(peerId: Int32) {
        self.reconnectedPeerIDs.append(peerId)
    }

    func sendNextMachine(targetId: Int32?) {
        self.sentNextMachineTargets.append(targetId)
    }

    func stopAutoReconnect() {
        self.stopAutoReconnectCount += 1
    }

    func sendMouseEvent(x: Int32, y: Int32, wheel: Int32, flags: Int32) {
        self.sentMouseEvents.append(MWBMouseEvent(x: x, y: y, wheel: wheel, flags: flags))
    }

    func sendKeyEvent(keyCode: Int32, flags: Int32) {
        self.sentKeyEvents.append(MWBKeyEvent(keyCode: keyCode, flags: flags))
    }

    func sendHideMouse() {}
    func sendClipboardText(_: String) {}
    func sendClipboardImage(_: Data) {}
    func sendClipboardImage(_: Data, to _: Int32?) {}
    func sendMachineMatrix(_: [String], twoRow _: Bool, swap _: Bool) {}
    func sendFileDrop(_: [URL]) {}
}

@MainActor
final class FakePasteboard: PasteboardAccessing {
    var changeCount = 0
    var isConcealedOrTransient = false
    var storedString: String?
    var storedPNGData: Data?
    var storedTIFFData: Data?
    var storedFileURLs: [URL]?
    var acceptImageWrites = true

    func readFileURLs() -> [URL]? { self.storedFileURLs }
    func readString() -> String? { self.storedString }
    func readPNGData() -> Data? { self.storedPNGData }
    func readImageTIFFData() -> Data? { self.storedTIFFData }

    func writeString(_ string: String) {
        self.storedString = string
        self.storedPNGData = nil
        self.storedFileURLs = nil
        self.changeCount += 1
    }

    func writeImageData(_ data: Data) -> Bool {
        guard self.acceptImageWrites else { return false }
        self.storedPNGData = data
        self.storedString = nil
        self.storedFileURLs = nil
        self.changeCount += 1
        return true
    }

    func writeFileURLs(_ urls: [URL]) {
        self.storedFileURLs = urls
        self.storedString = nil
        self.storedPNGData = nil
        self.changeCount += 1
    }
}

@MainActor
final class FakeScreenGeometry: ScreenGeometryProviding {
    var mainScreenFrame: CGRect?
    var allScreenFrames: [CGRect]

    init(mainScreenFrame: CGRect? = CGRect(x: 0, y: 0, width: 1920, height: 1080)) {
        self.mainScreenFrame = mainScreenFrame
        self.allScreenFrames = mainScreenFrame.map { [$0] } ?? []
    }
}

final class FakeClock: ClockProviding {
    private let current: OSAllocatedUnfairLock<TimeInterval>

    init(now: TimeInterval = 1000) {
        self.current = OSAllocatedUnfairLock(initialState: now)
    }

    func now() -> TimeInterval {
        self.current.withLock { $0 }
    }

    func advance(by seconds: TimeInterval) {
        self.current.withLock { $0 += seconds }
    }
}

@MainActor
final class FakeCursorController: CursorControlling {
    private(set) var hideCount = 0
    private(set) var unhideCount = 0
    private(set) var warpedPoints: [CGPoint] = []

    func hide() { self.hideCount += 1 }
    func unhide() { self.unhideCount += 1 }
    func warp(to point: CGPoint) { self.warpedPoints.append(point) }
}

@MainActor
final class FakeScreenCapturer: ScreenCapturing {
    var capturedPNG: Data?

    init(capturedPNG: Data? = Data([0x89, 0x50, 0x4E, 0x47])) {
        self.capturedPNG = capturedPNG
    }

    func captureMainScreenPNG() -> Data? {
        self.capturedPNG
    }
}

@MainActor
final class FakeInputEventSynthesizer: MBInputEventSynthesizing {
    private(set) var simulatedRemoteEvents: [RemoteEvent] = []
    private(set) var simulatedMouseEvents: [MWBMouseEvent] = []
    private(set) var simulatedKeyEvents: [MWBKeyEvent] = []

    func simulateRemoteEvent(_ event: RemoteEvent) {
        self.simulatedRemoteEvents.append(event)
    }

    func simulateMouseEvent(_ event: MWBMouseEvent) {
        self.simulatedMouseEvents.append(event)
    }

    func simulateKeyEvent(_ event: MWBKeyEvent) {
        self.simulatedKeyEvents.append(event)
    }
}

func makeIsolatedDefaults() -> (defaults: UserDefaults, cleanup: () -> Void) {
    let suiteName = "MagicBorderTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
}

func makeEventSnapshot(
    type: CGEventType,
    location: CGPoint = .zero,
    keyCode: Int64 = 0,
    scrollDeltaY: Int64 = 0,
    scrollDeltaX: Int64 = 0,
    mouseDeltaX: Int64 = 0,
    mouseDeltaY: Int64 = 0,
    flags: CGEventFlags = []
) -> EventSnapshot {
    EventSnapshot(
        location: location,
        type: type,
        keyCode: keyCode,
        scrollDeltaY: scrollDeltaY,
        scrollDeltaX: scrollDeltaX,
        mouseDeltaX: mouseDeltaX,
        mouseDeltaY: mouseDeltaY,
        flags: flags)
}
