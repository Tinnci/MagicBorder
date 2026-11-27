import MagicBorderKit
import SwiftUI

struct MachineDetailView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    let machine: Machine

    private var isLocalMachine: Bool {
        self.machine.state == .local
    }

    var body: some View {
        Form {
            Section {
                MachineDetailHeader(machine: self.machine)
            }

            Section(localizedString("Connection")) {
                LabeledContent(localizedString("Name"), value: self.machine.name)
                LabeledContent(
                    localizedString("Status"),
                    value: self.machine.isOnline ? localizedString("Online") : localizedString("Offline"))

                if self.machine.screenSize != .zero {
                    LabeledContent(
                        localizedString("Screen Size"),
                        value: self.screenSizeText)
                }

                if let peerID = self.machine.mwbPeerID {
                    LabeledContent(localizedString("MWB Peer ID"), value: "\(peerID)")
                }
            }

            Section(localizedString("Actions")) {
                Button {
                    self.networkManager.requestSwitch(to: self.machine.id)
                } label: {
                    Label(localizedString("Switch to Machine"), systemImage: "arrow.right.circle")
                }
                .disabled(self.isLocalMachine || !self.machine.isOnline)

                Button {
                    self.networkManager.reconnect(machineId: self.machine.id)
                } label: {
                    Label(localizedString("Restart Connection"), systemImage: "restart")
                }
                .disabled(self.isLocalMachine)

                Button(role: .destructive) {
                    self.networkManager.disconnect(machineId: self.machine.id)
                } label: {
                    Label(localizedString("Disconnect"), systemImage: "xmark.circle")
                }
                .disabled(self.isLocalMachine)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(self.machine.name)
    }

    private var screenSizeText: String {
        "\(Int(self.machine.screenSize.width)) x \(Int(self.machine.screenSize.height))"
    }
}

private struct MachineDetailHeader: View {
    let machine: Machine

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: self.machine.state == .local ? "macbook" : "desktopcomputer")
                .font(.system(size: 36))
                .foregroundStyle(
                    self.machine.isOnline || self.machine.state == .local
                        ? Color.accentColor : Color.secondary
                )
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(self.machine.name)
                    .font(.title3)
                    .bold()

                HStack(spacing: 6) {
                    StatusDot(active: self.machine.isOnline || self.machine.state == .local)
                    Text(self.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var statusText: String {
        switch self.machine.state {
        case .local:
            localizedString("Local Machine")
        case .discovered:
            localizedString("Discovered")
        case .connecting:
            localizedString("Connecting...")
        case .connected:
            localizedString("Online")
        case .active:
            localizedString("Active")
        }
    }
}
