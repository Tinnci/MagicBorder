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

        let service = await MainActor.run {
            let service = MWBCompatibilityService(
                localName: Host.current().localizedName ?? "Mac",
                localId: Int32.random(in: 1000...999999))
            service.start(securityKey: key)
            service.connectToHost(ip: ip)
            return service
        }

        print("Connecting to \(ip)…")

        for await event in service.events {
            switch event {
            case .connected(let peer):
                print("[CONNECTED] \(peer.name) (id=\(peer.id))")
            case .disconnected(let peer):
                print("[DISCONNECTED] \(peer.name) (id=\(peer.id))")
            case .machineSwitched(let peer):
                print("[ACTIVE] \(peer?.name ?? "local")")
            case .reconnectAttempt(let host):
                print("[RECONNECTING] \(host)")
            case .reconnectStopped(let host):
                print("[RECONNECT STOPPED] \(host)")
            case .log(let message):
                print("[LOG] \(message)")
            case .error(let message):
                print("[ERROR] \(message)")
            default:
                break
            }
        }
    }
}
