import Foundation
import Network
import Observation
import QuartzCore // For CACurrentMediaTime() or similar if needed

@MainActor
@Observable
public class MWBClient {
    public init() {}
    private var connection: NWConnection?
    private let crypto = MWBCrypto.shared
    private let machineName = Host.current().localizedName ?? "Mac"
    // Valid 32-bit ID (Simulated)
    private let machineID: Int32 = .random(in: 1000 ... 999999)

    public var status: String = "Idle"
    public var isConnected: Bool = false

    // Config
    var targetIP: String = ""
    var secretKey: String = ""

    public func connect(ip: String, key: String) {
        targetIP = ip
        secretKey = key
        status = "Deriving Keys..."

        // 1. Derive Keys
        crypto.deriveKey(from: key)

        guard crypto.sessionKey != nil else {
            status = "Key Derivation Failed"
            return
        }

        // 2. Connect TCP (Port 15101 for Data/Handshake)
        status = "Connecting to \(ip):15101..."
        let host = NWEndpoint.Host(ip)
        let port = NWEndpoint.Port(integerLiteral: 15101)

        let conn = NWConnection(to: .hostPort(host: host, port: port), using: .tcp)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    status = "Connected. Starting Handshake..."
                    print("TCP Ready. Starting Handshake Flow.")
                    startHandshakeFlow()
                case .failed(let error):
                    status = "Connection Failed: \(error)"
                    isConnected = false
                case .waiting(let error):
                    status = "Waiting: \(error)"
                default:
                    break
                }
            }
        }

        conn.start(queue: .main)
    }

    private func startHandshakeFlow() {
        // Step 1: Send Random Block (Initialization)
        // Original behavior: "Common.SendOrReceiveARandomDataBlockPerInitialIV"
        // It sends 16 bytes (AES Block Size) of random data encrypted (or just random data if it's the IV block? Need to check.
        // Based on analysis: "The first block is a handshake one containing random data."
        // We will send 64 bytes of random noise to be safe and wake up the stream.

        // Actually MWB protocol usually starts with `Handshake` packets directly after the crypto stream init.
        // Let's try sending the Handshake packets immediately, but Encrypted.

        sendHandshakePackets()
    }

    private func sendHandshakePackets() {
        // Construct Handshake Packet
        var packet = MWBPacket()
        packet.type = .handshake
        packet.src = machineID
        packet.des = 0 // Broadcast/Unknown
        packet.machineName = machineName // Need to implement string setting

        // Send 10 times as per protocol spec
        print("Sending 10 Handshake packets...")
        for _ in 0 ..< 10 {
            packet.finalizeForSend(magicNumber: crypto.magicNumber)
            send(packet: packet)
        }

        // Start Reading for Ask
        readLoop()
    }

    private func readLoop() {
        guard let conn = connection else { return }

        // Read 32 bytes (Standard Packet Size)
        // Note: MWB is a stream. We should read chunk by chunk.
        // But NWConnection might give us partials.
        // For simplicity, request 32 bytes.

        conn.receive(minimumIncompleteLength: 32, maximumLength: 64) {
            [weak self] content, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let data = content {
                    handleRawData(data)
                }

                if isComplete {
                    status = "Disconnected (EOF)"
                    isConnected = false
                    return
                }

                if error == nil {
                    // Continue reading
                    readLoop()
                } else {
                    status = "Read Error: \(error!)"
                }
            }
        }
    }

    private func handleRawData(_ encryptedData: Data) {
        // Decrypt
        guard let decrypted = crypto.decryptZeroPadded(encryptedData) else {
            print("Decryption failed for block of size \(encryptedData.count)")
            return
        }

        // Parse Packet
        // Note: Decrypted data might contain multiple packets or partials if we are not careful with boundaries.
        // Assuming 32-byte alignment for now.

        if decrypted.count >= 32 {
            let packet = MWBPacket(data: decrypted.prefix(32))

            // Check Magic
            if packet.magicHigh16 != (crypto.magicNumber >> 16) & 0xFFFF {
                print(
                    "Invalid Magic Number received: \(packet.magicHigh16) vs expected \((crypto.magicNumber >> 16) & 0xFFFF)")
                // return // Continue for now to see what happens
            }

            print("Received Packet Type: \(packet.type)")

            if packet.type == .handshakeAck {
                status = "Handshake Authenticated! Connected."
                isConnected = true
                print("SUCCESS: Handshake ACK received from Machine ID \(packet.src).")
            }
        }
    }

    private func send(packet: MWBPacket) {
        // Encrypt
        guard let encrypted = crypto.encryptZeroPadded(packet.data) else {
            print("Encryption failed")
            return
        }

        connection?.send(
            content: encrypted,
            completion: .contentProcessed { error in
                if let error {
                    print("Send error: \(error)")
                }
            })
    }
}
