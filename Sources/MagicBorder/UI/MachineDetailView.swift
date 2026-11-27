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
            let telemetry = self.networkManager.peerTelemetry[machine.id]

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

                if !isLocal {
                    Section(localizedString("Telemetry & Channels")) {
                        LabeledContent(
                            localizedString("Message Channel"),
                            value: (telemetry?.messageChannelConnected ?? machine.isOnline)
                                ? localizedString("Connected") : localizedString("Disconnected"))
                        if machine.mwbPeerID != nil {
                            LabeledContent(
                                localizedString("Clipboard Channel"),
                                value: (telemetry?.clipboardChannelConnected ?? false)
                                    ? localizedString("Connected") : localizedString("Pending"))
                        }
                        LabeledContent(
                            localizedString("Latency (RTT)"),
                            value: telemetry?.rttMs.map { "\($0) ms" } ?? "—")
                        if let lastHeartbeat = telemetry?.lastHeartbeatAt {
                            LabeledContent(
                                localizedString("Last Heartbeat"),
                                value: lastHeartbeat.formatted(date: .omitted, time: .standard))
                        }
                    }

                    Section(localizedString("Per-Peer Input Profile")) {
                        self.profileSection(for: machine)
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

    @ViewBuilder
    private func profileSection(for machine: Machine) -> some View {
        let store = self.networkManager.peerProfiles
        let fallback = self.networkManager.defaultInputProfile()
        let activeProfile = store.profile(for: machine.name, default: fallback)

        Toggle(
            localizedString("Override Global Input Settings"),
            isOn: Binding(
                get: { store.hasOverride(for: machine.name) },
                set: { enabled in
                    if enabled {
                        store.setOverride(activeProfile, for: machine.name)
                    } else {
                        store.clearOverride(for: machine.name)
                    }
                }))

        if store.hasOverride(for: machine.name) {
            Picker(
                localizedString("Modifier Mapping"),
                selection: Binding(
                    get: { activeProfile.modifierRemapMode },
                    set: { mode in
                        var updated = activeProfile
                        updated.modifierRemapMode = mode
                        store.setOverride(updated, for: machine.name)
                    })
            ) {
                Text(localizedString("Standard (Ctrl->Ctrl, Cmd->Win)")).tag(MBModifierRemapMode.standard)
                Text(localizedString("Mac Shortcuts (Swap Cmd <-> Ctrl)")).tag(MBModifierRemapMode.swapCommandControl)
            }

            Toggle(
                localizedString("Invert Remote Scroll Direction"),
                isOn: Binding(
                    get: { activeProfile.invertRemoteScroll },
                    set: { inverted in
                        var updated = activeProfile
                        updated.invertRemoteScroll = inverted
                        store.setOverride(updated, for: machine.name)
                    }))

            HStack {
                Text(localizedString("Remote Scroll Speed"))
                Slider(
                    value: Binding(
                        get: { activeProfile.remoteScrollSpeed },
                        set: { speed in
                            var updated = activeProfile
                            updated.remoteScrollSpeed = speed
                            store.setOverride(updated, for: machine.name)
                        }),
                    in: 0.25...2.5,
                    step: 0.25)
                Text("\(activeProfile.remoteScrollSpeed, specifier: "%.2fx")")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
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
