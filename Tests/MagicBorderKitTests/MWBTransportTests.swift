@testable import MagicBorderKit
import Network
import XCTest

@MainActor
final class MWBTransportTests: XCTestCase {
    func testDisconnectDelegatesToCompatibilityServiceForPeer() {
        let settings = MBCompatibilitySettings(defaults: UserDefaults(suiteName: "MagicBorderTests.\(UUID().uuidString)")!)
        let service = FakeMWBCompatibilityService()
        let transport = MBMWBTransport(
            localName: "Mac",
            localID: 1,
            settings: settings,
            service: service)
        let machine = Machine(id: UUID(), name: "Windows", state: .connected, mwbPeerID: 42)

        transport.disconnect(machine: machine)

        XCTAssertEqual(service.disconnectedPeerIDs, [42])
    }

    func testReconnectDelegatesToCompatibilityServiceForPeer() {
        let settings = MBCompatibilitySettings(defaults: UserDefaults(suiteName: "MagicBorderTests.\(UUID().uuidString)")!)
        let service = FakeMWBCompatibilityService()
        let transport = MBMWBTransport(
            localName: "Mac",
            localID: 1,
            settings: settings,
            service: service)
        let machine = Machine(id: UUID(), name: "Windows", state: .connected, mwbPeerID: 42)

        transport.reconnect(machine: machine)

        XCTAssertEqual(service.reconnectedPeerIDs, [42])
    }

    func testHostStringUsesConnectableIPv4Address() {
        let host = NWEndpoint.Host("192.168.1.20")

        XCTAssertEqual(MBMWBTransport.hostString(host), "192.168.1.20")
    }

    func testHostStringUsesBareDNSName() {
        let host = NWEndpoint.Host("windows-pc.local")

        XCTAssertEqual(MBMWBTransport.hostString(host), "windows-pc.local")
    }
}

@MainActor
private final class FakeMWBCompatibilityService: MWBCompatibilityServicing {
    let events: AsyncStream<MWBCompatibilityEvent>
    private let continuation: AsyncStream<MWBCompatibilityEvent>.Continuation

    private(set) var disconnectedPeerIDs: [Int32] = []
    private(set) var reconnectedPeerIDs: [Int32] = []

    init() {
        let stream = AsyncStream.makeStream(of: MWBCompatibilityEvent.self)
        self.events = stream.stream
        self.continuation = stream.continuation
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

    func sendNextMachine(targetId _: Int32?) {}
    func stopAutoReconnect() {}
    func sendMouseEvent(x _: Int32, y _: Int32, wheel _: Int32, flags _: Int32) {}
    func sendKeyEvent(keyCode _: Int32, flags _: Int32) {}
    func sendHideMouse() {}
    func sendClipboardText(_: String) {}
    func sendClipboardImage(_: Data) {}
    func sendClipboardImage(_: Data, to _: Int32?) {}
    func sendScreenCapture(_: Data, to _: Int32?) {}
    func sendMachineMatrix(_: [String], twoRow _: Bool, swap _: Bool) {}
    func sendFileDrop(_: [URL]) {}
}
