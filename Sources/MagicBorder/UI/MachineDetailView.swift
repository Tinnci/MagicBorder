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

            Section(MBLocalized("Connection")) {
                LabeledContent(MBLocalized("Name"), value: self.machine.name)
                LabeledContent(
                    MBLocalized("Status"),
                    value: self.machine.isOnline ? MBLocalized("Online") : MBLocalized("Offline"))

                if self.machine.screenSize != .zero {
                    LabeledContent(
                        MBLocalized("Screen Size"),
                        value: self.screenSizeText)
                }

                if let peerID = self.machine.mwbPeerID {
                    LabeledContent(MBLocalized("MWB Peer ID"), value: "\(peerID)")
                }
            }

            Section(MBLocalized("Actions")) {
                Button {
                    self.networkManager.requestSwitch(to: self.machine.id)
                } label: {
                    Label(MBLocalized("Switch to Machine"), systemImage: "arrow.right.circle")
                }
                .disabled(self.isLocalMachine || !self.machine.isOnline)

                Button {
                    self.networkManager.reconnect(machineId: self.machine.id)
                } label: {
                    Label(MBLocalized("Restart Connection"), systemImage: "restart")
                }
                .disabled(self.isLocalMachine)

                Button(role: .destructive) {
                    self.networkManager.disconnect(machineId: self.machine.id)
                } label: {
                    Label(MBLocalized("Disconnect"), systemImage: "xmark.circle")
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
                        ? Color.accentColor : Color.secondary)
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
            MBLocalized("Local Machine")
        case .discovered:
            MBLocalized("Discovered")
        case .connecting:
            MBLocalized("Connecting...")
        case .connected:
            MBLocalized("Online")
        case .active:
            MBLocalized("Active")
        }
    }
}
