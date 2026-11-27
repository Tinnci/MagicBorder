import CoreGraphics
import Foundation
import Network
import Testing

@testable import MagicBorderKit

@Suite("MWBTransport")
@MainActor
struct MWBTransportTests {
    @Test func disconnectDelegatesToCompatibilityServiceForPeer() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        let service = FakeMWBCompatibilityService()
        let transport = MBMWBTransport(
            localName: "Mac",
            localID: 1,
            settings: settings,
            service: service,
            screenGeometry: FakeScreenGeometry(),
            clock: FakeClock())
        let machine = Machine(id: UUID(), name: "Windows", state: .connected, mwbPeerID: 42)

        transport.disconnect(machine: machine)

        #expect(service.disconnectedPeerIDs == [42])
    }

    @Test func reconnectDelegatesToCompatibilityServiceForPeer() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        let service = FakeMWBCompatibilityService()
        let transport = MBMWBTransport(
            localName: "Mac",
            localID: 1,
            settings: settings,
            service: service,
            screenGeometry: FakeScreenGeometry(),
            clock: FakeClock())
        let machine = Machine(id: UUID(), name: "Windows", state: .connected, mwbPeerID: 42)

        transport.reconnect(machine: machine)

        #expect(service.reconnectedPeerIDs == [42])
    }

    @Test func activateNilStopsAutoReconnect() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        let service = FakeMWBCompatibilityService()
        let transport = MBMWBTransport(
            localName: "Mac",
            localID: 1,
            settings: settings,
            service: service,
            screenGeometry: FakeScreenGeometry(),
            clock: FakeClock())

        transport.activate(machine: nil)

        #expect(service.sentNextMachineTargets == [nil])
        #expect(service.stopAutoReconnectCount == 1)
    }

    @Test func centerRemoteCursorSendsNormalizedCenterMouseEvent() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        let service = FakeMWBCompatibilityService()
        let transport = MBMWBTransport(
            localName: "Mac",
            localID: 1,
            settings: settings,
            service: service,
            screenGeometry: FakeScreenGeometry(),
            clock: FakeClock())

        transport.centerRemoteCursor()

        #expect(service.sentMouseEvents == [MWBMouseEvent(x: 32767, y: 32767, wheel: 0, flags: 0x200)])
    }

    @Test func hostStringUsesConnectableIPv4AndDNSNames() {
        #expect(MBMWBTransport.hostString(NWEndpoint.Host("192.168.1.20")) == "192.168.1.20")
        #expect(MBMWBTransport.hostString(NWEndpoint.Host("windows-pc.local")) == "windows-pc.local")
    }
}
