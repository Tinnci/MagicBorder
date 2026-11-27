import CoreGraphics
import Darwin
import Foundation
import Network
import Testing

@testable import MagicBorderKit

@MainActor
private final class EventRecorder<Event: Sendable> {
    private var unconsumed: [Event] = []
    private var waiters: [UUID: (predicate: (Event) -> Bool, continuation: CheckedContinuation<Event?, Never>)] = [:]
    private var task: Task<Void, Never>?

    init(stream: AsyncStream<Event>) {
        self.task = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { break }
                if let matchedID = self.waiters.first(where: { $0.value.predicate(event) })?.key,
                    let waiter = self.waiters.removeValue(forKey: matchedID)
                {
                    waiter.continuation.resume(returning: event)
                } else {
                    self.unconsumed.append(event)
                }
            }
        }
    }

    func stop() {
        self.task?.cancel()
        self.task = nil
        let pending = self.waiters
        self.waiters.removeAll()
        for waiter in pending.values {
            waiter.continuation.resume(returning: nil)
        }
    }

    func next(
        timeout: Duration = .seconds(5),
        matching predicate: @escaping (Event) -> Bool
    ) async -> Event? {
        if let index = self.unconsumed.firstIndex(where: predicate) {
            return self.unconsumed.remove(at: index)
        }

        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            self.waiters[waiterID] = (predicate, continuation)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.cancelWaiter(id: waiterID)
            }
        }
    }

    private func cancelWaiter(id: UUID) {
        if let waiter = self.waiters.removeValue(forKey: id) {
            waiter.continuation.resume(returning: nil)
        }
    }
}

private func reserveEphemeralTCPPort() throws -> UInt16 {
    let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard socketFD >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer { Darwin.close(socketFD) }

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindStatus = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            Darwin.bind(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindStatus == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    var boundAddr = sockaddr_in()
    var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameStatus = withUnsafeMutablePointer(to: &boundAddr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            Darwin.getsockname(socketFD, sockPtr, &addrLen)
        }
    }
    guard nameStatus == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return UInt16(bigEndian: boundAddr.sin_port)
}

@Suite("Transport Loopback")
@MainActor
struct TransportLoopbackTests {
    @Test func modernTransportConnectsExchangesDataAndDisconnects() async throws {
        let serverPortValue = try reserveEphemeralTCPPort()
        let clientPortValue = try reserveEphemeralTCPPort()
        let serverPort = try #require(NWEndpoint.Port(rawValue: serverPortValue))
        let clientPort = try #require(NWEndpoint.Port(rawValue: clientPortValue))

        let serverID = UUID()
        let clientID = UUID()
        let key = "LoopbackTestSecurityKey!"

        let server = MBModernTransport(
            serviceType: "_magicborder._tcp",
            localName: "ServerMac",
            localID: serverID,
            securityKey: key,
            port: serverPort,
            screenGeometry: FakeScreenGeometry())
        let client = MBModernTransport(
            serviceType: "_magicborder._tcp",
            localName: "ClientMac",
            localID: clientID,
            securityKey: key,
            port: clientPort,
            screenGeometry: FakeScreenGeometry())

        let serverEvents = EventRecorder(stream: server.events)
        let clientEvents = EventRecorder(stream: client.events)
        defer {
            serverEvents.stop()
            clientEvents.stop()
            client.stop()
            server.stop()
        }

        server.start()
        client.start()
        try? await Task.sleep(for: .milliseconds(100))

        client.connectToHost(ip: "127.0.0.1", port: serverPortValue)

        let connectedOnServer = await serverEvents.next { event in
            if case .machineConnected(let machine) = event {
                return machine.id == clientID
            }
            return false
        }
        let connectedOnClient = await clientEvents.next { event in
            if case .machineConnected(let machine) = event {
                return machine.id == serverID
            }
            return false
        }

        #expect(connectedOnServer != nil)
        #expect(connectedOnClient != nil)

        client.sendClipboardText("hello-modern", activeMachineId: serverID)
        let receivedText = await serverEvents.next { event in
            if case .clipboardText(let text) = event {
                return text == "hello-modern"
            }
            return false
        }
        #expect(receivedText != nil)

        let pngSample = Data([0x89, 0x50, 0x4E, 0x47])
        client.sendClipboardImage(pngSample, activeMachineId: serverID)
        let receivedImage = await serverEvents.next { event in
            if case .clipboardImage(let data) = event {
                return data == pngSample
            }
            return false
        }
        #expect(receivedImage != nil)

        let snapshot = makeEventSnapshot(type: .keyDown, keyCode: 49)
        client.sendRemoteInput(snapshot: snapshot, activeMachineId: serverID)
        let receivedInput = await serverEvents.next { event in
            if case .remoteEvent(let remote) = event {
                return remote.type == .keyDown && remote.keyCode == 49
            }
            return false
        }
        #expect(receivedInput != nil)

        let serverMachine = Machine(id: serverID, name: "ServerMac", state: .connected)
        client.disconnect(machine: serverMachine)
        let disconnectedOnClient = await clientEvents.next { event in
            if case .machineDisconnected(let machineID) = event {
                return machineID == serverID
            }
            return false
        }
        #expect(disconnectedOnClient != nil)
    }

    @Test func modernTransportRejectsMismatchedSecurityKey() async throws {
        let serverPortValue = try reserveEphemeralTCPPort()
        let clientPortValue = try reserveEphemeralTCPPort()
        let serverPort = try #require(NWEndpoint.Port(rawValue: serverPortValue))
        let clientPort = try #require(NWEndpoint.Port(rawValue: clientPortValue))

        let server = MBModernTransport(
            serviceType: "_magicborder._tcp",
            localName: "ServerMac",
            localID: UUID(),
            securityKey: "ExpectedSecretKey1234",
            port: serverPort,
            screenGeometry: FakeScreenGeometry())
        let client = MBModernTransport(
            serviceType: "_magicborder._tcp",
            localName: "ClientMac",
            localID: UUID(),
            securityKey: "WrongSecretKey5678",
            port: clientPort,
            screenGeometry: FakeScreenGeometry())

        let serverEvents = EventRecorder(stream: server.events)
        defer {
            serverEvents.stop()
            client.stop()
            server.stop()
        }

        server.start()
        client.start()
        try? await Task.sleep(for: .milliseconds(100))

        client.connectToHost(ip: "127.0.0.1", port: serverPortValue)

        let unexpectedConnect = await serverEvents.next(timeout: .milliseconds(450)) { event in
            if case .machineConnected = event {
                return true
            }
            return false
        }
        #expect(unexpectedConnect == nil)
    }

    @Test func mwbServiceRejectsShortKeyOnStartAndConnect() async {
        let service = MWBCompatibilityService(
            localName: "MacHost",
            localId: 1001,
            pasteboard: FakePasteboard())
        let events = EventRecorder(stream: service.events)
        defer {
            events.stop()
            service.stop()
        }

        service.start(securityKey: "too-short")
        let logEvent = await events.next { event in
            if case .log(let message) = event {
                return message.contains("security key too short")
            }
            return false
        }
        #expect(logEvent != nil)

        service.connectToHost(ip: "127.0.0.1")
        let errorEvent = await events.next { event in
            if case .error(let message) = event {
                return message.contains("security key")
            }
            return false
        }
        #expect(errorEvent != nil)
    }

    @Test func mwbServiceConnectsOverLoopbackAndRelaysInputMatrixAndClipboard() async throws {
        let serverMsgPort = try reserveEphemeralTCPPort()
        let serverClipPort = try reserveEphemeralTCPPort()
        let clientMsgPort = try reserveEphemeralTCPPort()
        let clientClipPort = try reserveEphemeralTCPPort()
        let securityKey = "0123456789ABCDEF"

        let server = MWBCompatibilityService(
            localName: "WindowsHost",
            localId: 2001,
            messagePort: serverMsgPort,
            clipboardPort: serverClipPort,
            pasteboard: FakePasteboard())
        let client = MWBCompatibilityService(
            localName: "MacClient",
            localId: 2002,
            messagePort: clientMsgPort,
            clipboardPort: clientClipPort,
            pasteboard: FakePasteboard())

        let serverEvents = EventRecorder(stream: server.events)
        let clientEvents = EventRecorder(stream: client.events)
        defer {
            serverEvents.stop()
            clientEvents.stop()
            client.stop()
            server.stop()
        }

        server.start(securityKey: securityKey)
        client.start(securityKey: securityKey)

        let serverStarted = await serverEvents.next { event in
            if case .log(let message) = event {
                return message.contains("MWB service started")
            }
            return false
        }
        let clientStarted = await clientEvents.next { event in
            if case .log(let message) = event {
                return message.contains("MWB service started")
            }
            return false
        }
        #expect(serverStarted != nil)
        #expect(clientStarted != nil)

        try? await Task.sleep(for: .milliseconds(80))
        client.connectToHost(ip: "127.0.0.1", messagePort: serverMsgPort, clipboardPort: serverClipPort)

        let serverSawClient = await serverEvents.next { event in
            if case .connected(let peer) = event {
                return peer.id == 2002
            }
            return false
        }
        let clientSawServer = await clientEvents.next { event in
            if case .connected(let peer) = event {
                return peer.id == 2001
            }
            return false
        }
        #expect(serverSawClient != nil)
        #expect(clientSawServer != nil)

        client.sendMouseEvent(x: 12000, y: 24000, wheel: 0, flags: 0x200)
        let mouseReceived = await serverEvents.next { event in
            if case .remoteMouse(let mouse) = event {
                return mouse == MWBMouseEvent(x: 12000, y: 24000, wheel: 0, flags: 0x200)
            }
            return false
        }
        #expect(mouseReceived != nil)

        client.sendKeyEvent(keyCode: 65, flags: 0)
        let keyReceived = await serverEvents.next { event in
            if case .remoteKey(let key) = event {
                return key == MWBKeyEvent(keyCode: 65, flags: 0)
            }
            return false
        }
        #expect(keyReceived != nil)

        client.sendMachineMatrix(["MacClient", "WindowsHost"], twoRow: true, swap: false)
        let firstSlotReceived = await serverEvents.next { event in
            if case .machineMatrix(let names) = event {
                return names == ["MacClient"]
            }
            return false
        }
        let secondSlotReceived = await serverEvents.next { event in
            if case .machineMatrix(let names) = event {
                return names == ["WindowsHost"]
            }
            return false
        }
        let optionsReceived = await serverEvents.next { event in
            if case .matrixOptionsUpdated(let twoRow, let swap) = event {
                return twoRow && !swap
            }
            return false
        }
        #expect(firstSlotReceived != nil)
        #expect(secondSlotReceived != nil)
        #expect(optionsReceived != nil)

        client.sendClipboardText("hello-mwb")
        let clipReceived = await serverEvents.next { event in
            if case .clipboardText(let text) = event {
                return text == "hello-mwb"
            }
            return false
        }
        #expect(clipReceived != nil)

        client.disconnect(peerId: 2001)
    }
}
