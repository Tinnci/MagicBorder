import MagicBorderKit
import SwiftUI

struct MachineInspectorPopover: View {
    @Environment(MBAppController.self) private var controller
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBOverlayPreferencesStore.self) private var overlayPreferences

    @AppStorage("dragDropOverlayShowDevice") private var defaultShowDevice = true
    @AppStorage("dragDropOverlayShowProgress") private var defaultShowProgress = true
    @AppStorage("dragDropOverlayScale") private var defaultScale = 1.0
    @AppStorage("dragDropOverlayPosition") private var defaultPositionRaw = "top"

    let machineID: UUID
    var onDiagnoseHost: ((String) -> Void)?

    private var machine: Machine? {
        self.networkManager.visibleMachines().first(where: { $0.id == self.machineID })
    }

    var body: some View {
        Group {
            if let machine = self.machine {
                let isLocal = machine.state == .local
                let isFocused =
                    (isLocal && self.networkManager.activeMachineId == nil)
                    || (self.networkManager.activeMachineId == machine.id)
                let telemetry = self.networkManager.peerTelemetry[machine.id]

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        self.headerSection(machine: machine, isLocal: isLocal, isFocused: isFocused)
                        self.actionsSection(machine: machine, isLocal: isLocal)

                        if !isLocal {
                            Divider()
                            self.telemetrySection(machine: machine, telemetry: telemetry)
                            Divider()
                            self.profileSection(for: machine)
                        }

                        Divider()
                        self.overlaySection(for: machine)
                    }
                    .padding(16)
                }
                .frame(width: 340)
                .frame(maxHeight: 520)
            } else {
                ContentUnavailableView(
                    localizedString("Device Offline"),
                    systemImage: "desktopcomputer.trianglebadge.exclamationmark"
                )
                .frame(width: 300, height: 180)
            }
        }
    }

    @ViewBuilder
    private func headerSection(machine: Machine, isLocal: Bool, isFocused: Bool) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName: isLocal ? "macbook" : (machine.mwbPeerID != nil ? "pc" : "desktopcomputer")
            )
            .font(.system(size: 28))
            .foregroundStyle(isFocused || machine.isOnline || isLocal ? Color.accentColor : .secondary)
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(machine.name)
                        .font(.headline)
                        .lineLimit(1)

                    if let peerID = machine.mwbPeerID {
                        Text("MWB #\(peerID)")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    } else if !isLocal {
                        Text(localizedString("Mac-to-Mac"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                HStack(spacing: 6) {
                    StatusDot(active: machine.isOnline || isLocal)
                    Text(self.statusText(machine: machine, isLocal: isLocal, isFocused: isFocused))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if machine.screenSize != .zero {
                        Text("• \(Int(machine.screenSize.width))×\(Int(machine.screenSize.height))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func actionsSection(machine: Machine, isLocal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if isLocal {
                        self.networkManager.forceReturnToLocal(reason: "popover")
                    } else {
                        self.networkManager.requestSwitch(to: machine.id)
                    }
                } label: {
                    Label(
                        isLocal ? localizedString("Return Control Here") : localizedString("Switch"),
                        systemImage: "arrow.right.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isLocal && !machine.isOnline)

                Button {
                    self.networkManager.pushCurrentClipboard()
                } label: {
                    Label(localizedString("Send Clipboard Now"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(self.networkManager.connectedMachines.isEmpty)
            }

            if !isLocal {
                HStack(spacing: 8) {
                    if let onDiagnoseHost = self.onDiagnoseHost {
                        Button {
                            onDiagnoseHost(self.savedHostAddress(for: machine))
                        } label: {
                            Label(localizedString("Diagnose"), systemImage: "stethoscope")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        self.networkManager.reconnect(machineId: machine.id)
                    } label: {
                        Label(localizedString("Restart Connection"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button(role: .destructive) {
                        self.networkManager.disconnect(machineId: machine.id)
                    } label: {
                        Label(localizedString("Disconnect"), systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func telemetrySection(machine: Machine, telemetry: PeerTelemetry?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localizedString("Telemetry & Channels"))
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text(localizedString("Message Channel"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        (telemetry?.messageChannelConnected ?? machine.isOnline)
                            ? localizedString("Connected") : localizedString("Disconnected")
                    )
                    .font(.caption.weight(.medium))
                }
                if machine.mwbPeerID != nil {
                    GridRow {
                        Text(localizedString("Clipboard Channel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(
                            (telemetry?.clipboardChannelConnected ?? false)
                                ? localizedString("Connected") : localizedString("Pending")
                        )
                        .font(.caption.weight(.medium))
                    }
                }
                GridRow {
                    Text(localizedString("Latency (RTT)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(telemetry?.rttMs.map { "\($0) ms" } ?? "—")
                        .font(.caption.monospacedDigit())
                }
                if let lastHeartbeat = telemetry?.lastHeartbeatAt {
                    GridRow {
                        Text(localizedString("Last Heartbeat"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(lastHeartbeat.formatted(date: .omitted, time: .standard))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func profileSection(for machine: Machine) -> some View {
        let store = self.networkManager.peerProfiles
        let fallback = self.networkManager.defaultInputProfile()
        let activeProfile = store.profile(for: machine.name, default: fallback)

        VStack(alignment: .leading, spacing: 8) {
            Text(localizedString("Per-Peer Input Profile"))
                .font(.subheadline.weight(.semibold))

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
                    })
            )
            .font(.caption)

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
                    Text(localizedString("Mac Shortcuts (Swap Cmd <-> Ctrl)")).tag(
                        MBModifierRemapMode.swapCommandControl)
                }
                .font(.caption)

                Toggle(
                    localizedString("Invert Remote Scroll Direction"),
                    isOn: Binding(
                        get: { activeProfile.invertRemoteScroll },
                        set: { inverted in
                            var updated = activeProfile
                            updated.invertRemoteScroll = inverted
                            store.setOverride(updated, for: machine.name)
                        })
                )
                .font(.caption)

                HStack {
                    Text(localizedString("Remote Scroll Speed"))
                        .font(.caption)
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
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func overlaySection(for machine: Machine) -> some View {
        let defaults = self.defaultOverlayPreferences
        let activeOverlay = self.overlayPreferences.preferences(for: machine.name, default: defaults)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localizedString("Per-Device Override"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(localizedString("Preview Overlay")) {
                    self.controller.previewDragDropOverlay()
                }
                .controlSize(.mini)
                .buttonStyle(.bordered)
            }

            Toggle(
                localizedString("Override Global Settings"),
                isOn: Binding(
                    get: { self.overlayPreferences.hasOverride(for: machine.name) },
                    set: { enabled in
                        if enabled {
                            self.overlayPreferences.setOverride(activeOverlay, for: machine.name)
                        } else {
                            self.overlayPreferences.clearOverride(for: machine.name)
                        }
                    })
            )
            .font(.caption)

            if self.overlayPreferences.hasOverride(for: machine.name) {
                Toggle(
                    localizedString("Show Device Name"),
                    isOn: Binding(
                        get: { activeOverlay.showDevice },
                        set: { show in
                            var updated = activeOverlay
                            updated.showDevice = show
                            self.overlayPreferences.setOverride(updated, for: machine.name)
                        })
                )
                .font(.caption)

                Toggle(
                    localizedString("Show Progress"),
                    isOn: Binding(
                        get: { activeOverlay.showProgress },
                        set: { show in
                            var updated = activeOverlay
                            updated.showProgress = show
                            self.overlayPreferences.setOverride(updated, for: machine.name)
                        })
                )
                .font(.caption)

                HStack {
                    Text(localizedString("Size"))
                        .font(.caption)
                    Slider(
                        value: Binding(
                            get: { activeOverlay.scale },
                            set: { scale in
                                var updated = activeOverlay
                                updated.scale = scale
                                self.overlayPreferences.setOverride(updated, for: machine.name)
                            }),
                        in: 0.85...1.3,
                        step: 0.05)
                    Text("\(Int(activeOverlay.scale * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Picker(
                    localizedString("Position"),
                    selection: Binding(
                        get: { activeOverlay.position.rawValue },
                        set: { raw in
                            var updated = activeOverlay
                            updated.position = MBOverlayPosition(rawValue: raw) ?? .top
                            self.overlayPreferences.setOverride(updated, for: machine.name)
                        })
                ) {
                    Text(localizedString("Top")).tag("top")
                    Text(localizedString("Bottom")).tag("bottom")
                    Text(localizedString("Top Left")).tag("topLeading")
                    Text(localizedString("Top Right")).tag("topTrailing")
                    Text(localizedString("Bottom Left")).tag("bottomLeading")
                    Text(localizedString("Bottom Right")).tag("bottomTrailing")
                }
                .font(.caption)
            }
        }
    }

    private var defaultOverlayPreferences: MBOverlayPreferences {
        MBOverlayPreferences(
            showDevice: self.defaultShowDevice,
            showProgress: self.defaultShowProgress,
            scale: self.defaultScale,
            position: MBOverlayPosition(rawValue: self.defaultPositionRaw) ?? .top)
    }

    private func savedHostAddress(for machine: Machine) -> String {
        if let saved = self.networkManager.savedHosts.hosts.first(where: {
            $0.name.caseInsensitiveCompare(machine.name) == .orderedSame
        }) {
            return saved.address
        }
        return self.networkManager.savedHosts.hosts.first?.address ?? ""
    }

    private func statusText(machine: Machine, isLocal: Bool, isFocused: Bool) -> String {
        if isFocused {
            return localizedString("Controlling")
        }
        if isLocal {
            return localizedString("Local Machine")
        }
        return machine.isOnline ? localizedString("Online") : localizedString("Offline")
    }
}
