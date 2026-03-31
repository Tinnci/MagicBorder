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

        await MainActor.run {
            let service = MWBCompatibilityService(
                localName: Host.current().localizedName ?? "Mac",
                localId: Int32.random(in: 1000 ... 999999))
            service.start(securityKey: key)
            service.connectToHost(ip: ip)
        }

        print("Connecting to \(ip)…")

        // Keep running to receive events
        while true {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1000000000)
        }
    }
}
