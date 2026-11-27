import AppKit
import MagicBorderKit
import Network
import SwiftUI

struct DiscoveredMachinesListView: View {
    var networkManager: MBNetworkManager

    var body: some View {
        List {
            if let ip = self.networkManager.localIPv4Addresses().first {
                Section(localizedString("This Mac")) {
                    HStack {
                        Label(ip, systemImage: "wifi")
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        Button(localizedString("Copy")) {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(ip, forType: .string)
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section(localizedString("Discovered Peers")) {
                ForEach(self.networkManager.discoveredPeers) { peer in
                    let isConnected = self.networkManager.connectedMachines.contains {
                        $0.name.caseInsensitiveCompare(peer.name) == .orderedSame
                    }
                    HStack {
                        Image(systemName: peer.type == .scanned ? "pc" : "laptopcomputer")
                            .font(.title2)
                            .foregroundStyle(isConnected ? .green : Color.accentColor)

                        VStack(alignment: .leading) {
                            Text(peer.name)
                                .font(.headline)
                            Text(Self.formattedEndpoint(peer.endpoint))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isConnected {
                            Label(localizedString("Connected"), systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Button(localizedString("Connect")) {
                                self.networkManager.connect(to: peer.endpoint)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(localizedString("Discovered Machines"))
        .toolbar {
            ToolbarItem {
                Button {
                    self.networkManager.rescanNetwork()
                } label: {
                    Label(localizedString("Rescan"), systemImage: "arrow.clockwise")
                }
            }
        }
        .overlay {
            if self.networkManager.discoveredPeers.isEmpty {
                ContentUnavailableView(
                    localizedString("Scanning for machines..."),
                    systemImage: "antenna.radiowaves.left.and.right")
            }
        }
    }

    private static func formattedEndpoint(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, let port):
            return "\(host):\(port.rawValue)"
        case .service(let name, _, _, _):
            return "\(name) (Bonjour)"
        default:
            return String(describing: endpoint)
        }
    }
}
