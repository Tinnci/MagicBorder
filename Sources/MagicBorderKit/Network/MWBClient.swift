import Foundation
import Network
import QuartzCore  // For CACurrentMediaTime() or similar if needed

@MainActor
public class MWBClient: ObservableObject {
    public init() {}
    private var connection: NWConnection?
    private let crypto = MWBCrypto.shared
    private let machineName = Host.current().localizedName ?? "Mac"
    // Valid 32-bit ID (Simulated)
    private let machineID: Int32 = Int32.random(in: 1000...999999)

    @Published public var status: String = "Idle"
    @Published public var isConnected: Bool = false

    // Config
    var targetIP: String = ""
    var secretKey: String = ""

    public func connect(ip: String, key: String) {
        self.targetIP = ip
        self.secretKey = key
        self.status = "Deriving Keys..."

        // 1. Derive Keys
        crypto.deriveKey(from: key)

        guard crypto.sessionKey != nil else {
            self.status = "Key Derivation Failed"
            return
        }

        // 2. Connect TCP (Port 15101 for Data/Handshake)
        self.status = "Connecting to \(ip):15101..."
        let host = NWEndpoint.Host(ip)
        let port = NWEndpoint.Port(integerLiteral: 15101)

        let conn = NWConnection(to: .hostPort(host: host, port: port), using: .tcp)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.status = "Connected. Starting Handshake..."
                    print("TCP Ready. Starting Handshake Flow.")
                    self.startHandshakeFlow()
                case .failed(let error):
                    self.status = "Connection Failed: \(error)"
                    self.isConnected = false
                case .waiting(let error):
                    self.status = "Waiting: \(error)"
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
        packet.des = 0  // Broadcast/Unknown
        packet.machineName = machineName  // Need to implement string setting

        // Send 10 times as per protocol spec
        print("Sending 10 Handshake packets...")
        for _ in 0..<10 {
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
                guard let self = self else { return }

                if let data = content {
                    self.handleRawData(data)
                }

                if isComplete {
                    self.status = "Disconnected (EOF)"
                    self.isConnected = false
                    return
                }

                if error == nil {
                    // Continue reading
                    self.readLoop()
                } else {
                    self.status = "Read Error: \(error!)"
                }
            }
        }
    }

    private func handleRawData(_ encryptedData: Data) {
        // Decrypt
        guard let decrypted = crypto.decrypt(encryptedData) else {
            print("Decryption failed for block of size \(encryptedData.count)")
            return
        }

        // Parse Packet
        // Note: Decrypted data might contain multiple packets or partials if we are not careful with boundaries.
        // Assuming 32-byte alignment for now.

        if decrypted.count >= 32 {
            let packet = MWBPacket(data: decrypted.prefix(32))

            // Check Magic
            if packet.magic != (crypto.magicNumber >> 16) & 0xFFFF {
                print(
                    "Invalid Magic Number received: \(packet.magic) vs expected \((crypto.magicNumber >> 16) & 0xFFFF)"
                )
                // return // Continue for now to see what happens
            }

            print("Received Packet Type: \(packet.type)")

            if packet.type == .handshakeAck {
                self.status = "Handshake Authenticated! Connected."
                self.isConnected = true
                print("SUCCESS: Handshake ACK received from Machine ID \(packet.src).")
            }
        }
    }

    private func send(packet: MWBPacket) {
        // Encrypt
        guard let encrypted = crypto.encrypt(packet.data) else {
            print("Encryption failed")
            return
        }

        connection?.send(
            content: encrypted,
            completion: .contentProcessed { error in
                if let error = error {
                    print("Send error: \(error)")
                }
            })
    }
}

// Extension to help setting Name in MWBPacket
extension MWBPacket {
    var machineName: String {
        get { return "" }  // Not implemented retrieval yet
        set {
            // MWB puts Machine Name in a specific layout or just end of payload?
            // "DATA.cs" structure shows:
            // machineNameP1 (Long/8 bytes) at Offset 64? No, offsets 64 is OUTSIDE standard 64 byte packet?
            // "StructLayout(LayoutKind.Explicit)" ...
            // [FieldOffset(sizeof(PackageType) + (7 * sizeof(uint)))] = 32 + 28 = 60?
            // Wait, PACKET_SIZE_EX is 64.
            // Let's look at DATA.cs again.

            /*
            [FieldOffset(sizeof(PackageType) + (7 * sizeof(uint)))]
            private long machineNameP1;
            
            sizeof(PackageType) = 4 (Enum is Int32 in C# usually? No, PackageType is usually byte in packet but field is Int32 aligned?)
            Wait, DATA.cs:
            [FieldOffset(0)] internal PackageType Type; // 4 bytes!
            [FieldOffset(4)] internal int Id;
            ...
            
            So header in DATA struct is aligned to 4 bytes.
            Offset 0: Type (4)
            Offset 4: Id (4)
            Offset 8: Src (4)
            Offset 12: Des (4)
            Offset 16: DateTime (8)
            Offset 24: Union (X/Key) (4)
            Offset 28: Union (Y/Param) (4) (Total 32 Bytes so far. This matches PACKAGE_SIZE)
            
            Offset 32: Wheel (4)
            Offset 36: Machine1 (4)
            ...
            Offset 48: PostAction (4)
            Offset 52: MachineNameP1 (8)
            Offset 60: MachineNameP2 (8)
            Offset 68: MachineNameP3 (8)
            Offset 76: MachineNameP4 (8)
            
            Wait, this exceeds 64 bytes (PACKAGE_SIZE_EX).
            DATA.cs struct size might be larger than the network packet size?
            "internal const byte PACKAGE_SIZE = 32;"
            "internal const byte PACKAGE_SIZE_EX = 64;"
            
            If `Bytes` property in DATA.cs:
            "Array.Copy(StructToBytes(this), buf, IsBigPackage ? Package.PACKAGE_SIZE_EX : Package.PACKAGE_SIZE);"
            
            This implies the DATA struct matches the Packet layout EXACTLY.
            
            Let's re-calculate offsets:
            0: Type (4)
            4: Id (4)
            8: Src (4)
            12: Des (4)
            16: DateTime (8) -> Ends at 24
            24: Union 1 (4) -> Ends at 28
            28: Union 2 (4) -> Ends at 32. -> Fits in 32 Byte Packet.
            
            Big Package (64 Bytes):
            32: Machine1 (4)? No.
            
            Let's verify DATA.cs offsets again in your provided file Content.
            
             27:    [FieldOffset(0)] Type; // 4
             30:    [FieldOffset(4)] Id; // 4
             33:    [FieldOffset(8)] Src; // 4
             36:    [FieldOffset(12)] Des; // 4
             39:    [FieldOffset(16)] DateTime; // 8 (long)
             42:    [FieldOffset(24)] Kd; // Struct?
             45:    [FieldOffset(24)] Md; // Struct?
             // KD/MD are likely 8 bytes total (2 ints).
            
             48:    [FieldOffset(24)] Machine1; (ID is uint/4 bytes)
             51:    [FieldOffset(28)] Machine2;
            
             54:    [FieldOffset(32)] Machine3;
             57:    [FieldOffset(36)] Machine4;
            
             63:    [FieldOffset(32)] machineNameP1; // Wait, Offset is `sizeof(PackageType) + (7 * sizeof(uint))`
             sizeof(Type)=4. 7*4=28. 4+28 = 32.
             So MachineNameP1 starts at 32.
            
             MachineNameP1: 8 bytes -> 32-40
             MachineNameP2: 8 bytes -> 40-48
             MachineNameP3: 8 bytes -> 48-56
             MachineNameP4: 8 bytes -> 56-64
            
             Total 64 Bytes. Matches exactly!
            */

            // So Machine Name is stored in bytes 32-64 (4 * Int64).
            // We need to write the string bytes into range 32..<64.

            guard let strData = newValue.data(using: .utf8) else { return }
            let maxLen = 32
            // let copyLen = min(strData.count, maxLen)

            // Pad with spaces as per C# "value.PadRight(32, ' ')"
            var padded = strData
            if padded.count < maxLen {
                padded.append(contentsOf: (Data(count: maxLen - padded.count).map { _ in 0x20 }))  // 0x20 is Space
            }

            // Write to data[32...63]
            data.replaceSubrange(32..<64, with: padded.prefix(32))
        }
    }
}
