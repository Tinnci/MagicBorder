import MagicBorderKit
import SwiftUI

struct MachineDetailView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    let machineID: UUID

    private var machine: Machine? {
        self.networkManager.visibleMachines().first(where: { $0.id == self.machineID })
    }

    var body: some View {
        if let machine = self.machine {
            let isLocal = machine.state == .local
            let isFocused =
                (isLocal && self.networkManager.activeMachineId == nil)
                || (self.networkManager.activeMachineId == machine.id)

            Form {
                Section {
                    MachineDetailHeader(machine: machine, isFocused: isFocused)
                }

                Section(localizedString("Connection")) {
                    LabeledContent(localizedString("Name"), value: machine.name)
                    LabeledContent(
                        localizedString("Status"),
                        value: machine.isOnline || isLocal ? localizedString("Online") : localizedString("Offline"))

                    if machine.screenSize != .zero {
                        LabeledContent(
                            localizedString("Screen Size"),
                            value: "\(Int(machine.screenSize.width)) x \(Int(machine.screenSize.height))")
                    }

                    if let peerID = machine.mwbPeerID {
                        LabeledContent(localizedString("MWB Peer ID"), value: "\(peerID)")
                    }
                }

                Section(localizedString("Actions")) {
                    Button {
                        if isLocal {
                            self.networkManager.forceReturnToLocal(reason: "detail-view")
                        } else {
                            self.networkManager.requestSwitch(to: machine.id)
                        }
                    } label: {
                        Label(
                            isLocal ? localizedString("Return Control Here") : localizedString("Switch to Machine"),
                            systemImage: "arrow.right.circle")
                    }
                    .disabled(!isLocal && !machine.isOnline)

                    Button {
                        self.networkManager.pushCurrentClipboard()
                    } label: {
                        Label(localizedString("Send Clipboard Now"), systemImage: "doc.on.clipboard")
                    }
                    .disabled(self.networkManager.connectedMachines.isEmpty)

                    if !isLocal {
                        Button {
                            self.networkManager.reconnect(machineId: machine.id)
                        } label: {
                            Label(localizedString("Restart Connection"), systemImage: "restart")
                        }

                        Button(role: .destructive) {
                            self.networkManager.disconnect(machineId: machine.id)
                        } label: {
                            Label(localizedString("Disconnect"), systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(machine.name)
        } else {
            ContentUnavailableView(
                localizedString("Device Offline"),
                systemImage: "desktopcomputer.trianglebadge.exclamationmark")
        }
    }
}

private struct MachineDetailHeader: View {
    let machine: Machine
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(
                systemName: self.machine.state == .local
                    ? "macbook" : (self.machine.mwbPeerID != nil ? "pc" : "desktopcomputer")
            )
            .font(.system(size: 36))
            .foregroundStyle(
                self.isFocused || self.machine.isOnline || self.machine.state == .local
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
        if self.isFocused {
            return localizedString("Controlling")
        }
        switch self.machine.state {
        case .local:
            return localizedString("Local Machine")
        case .discovered:
            return localizedString("Discovered")
        case .connecting:
            return localizedString("Connecting...")
        case .connected:
            return localizedString("Online")
        case .active:
            return localizedString("Active")
        }
    }
}
