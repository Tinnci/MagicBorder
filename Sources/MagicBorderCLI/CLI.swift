import Foundation
import MagicBorderKit

@main
struct CLI {
    static func main() async {
        let args = ProcessInfo.processInfo.arguments

        guard args.count >= 3 else {
            print("Usage: MagicBorderCLI <IP_ADDRESS> <SECURITY_KEY>")
            exit(1)
        }

        let ip = args[1]
        let key = args[2]

        print("MagicBorder CLI - Windows Compatibility Mode")
        print("Target: \(ip)")
        print("Key: \(String(repeating: "*", count: key.count))")

        let client = MWBClient()
        client.connect(ip: ip, key: key)

        // Keep running to listen
        while true {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1000000000)
            if client.isConnected {
                // print("Heartbeat...")
            }
        }
    }
}
