@testable import MagicBorderKit
import Network
import XCTest

@MainActor
final class MWBTransportTests: XCTestCase {
    func testHostStringUsesConnectableIPv4Address() {
        let host = NWEndpoint.Host("192.168.1.20")

        XCTAssertEqual(MBMWBTransport.hostString(host), "192.168.1.20")
    }

    func testHostStringUsesBareDNSName() {
        let host = NWEndpoint.Host("windows-pc.local")

        XCTAssertEqual(MBMWBTransport.hostString(host), "windows-pc.local")
    }
}
