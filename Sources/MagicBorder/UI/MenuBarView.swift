import AppKit
import MagicBorderKit
import SwiftUI

struct MenuBarView: View {
    @Environment(MBAppController.self) private var controller
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    private var hasConnectedPeers: Bool {
        !self.networkManager.connectedMachines.isEmpty
    }

    var body: some View {
        @Bindable var controller = controller
        @Bindable var networkManager = networkManager
        @Bindable var sessionCoordinator = networkManager.sessionCoordinator

        VStack(alignment: .leading, spacing: 12) {
            self.headerRow(activeName: sessionCoordinator.activeMachineName)

            if !self.accessibilityService.isTrusted {
                self.accessibilityWarningBox()
            }

            Divider()

            self.devicesSection(activeMachineId: sessionCoordinator.activeMachineId)

            Divider()

            self.quickControlsGrid()

            Divider()

            self.togglesSection(controller: controller, networkManager: networkManager)

            Divider()

            self.footerRow()
        }
        .padding(14)
        .frame(width: 292)
    }

    @ViewBuilder
    private func headerRow(activeName: String) -> some View {
        HStack(spacing: 8) {
            StatusDot(active: self.hasConnectedPeers && !self.networkManager.isInputPaused)

            VStack(alignment: .leading, spacing: 1) {
                Text(localizedString("MagicBorder"))
                    .font(.headline)
                Text(self.statusLine(activeName: activeName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                self.openDashboard()
            } label: {
                Image(systemName: "macwindow")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(localizedString("Open Dashboard..."))
            .accessibilityLabel(localizedString("Open Dashboard..."))
        }
    }

    @ViewBuilder
    private func accessibilityWarningBox() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(localizedString("Accessibility Permission Needed"))
                .font(.caption.weight(.medium))
            Spacer()
            Button(localizedString("Grant Access")) {
                self.accessibilityService.openSystemSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func devicesSection(activeMachineId: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localizedString("Devices"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if self.hasConnectedPeers {
                self.deviceRow(
                    title: self.networkManager.localDisplayName,
                    subtitle: localizedString("This Mac"),
                    systemImage: "macbook",
                    rttMs: nil,
                    shortcutHint: "⌃⌥1",
                    isSelected: activeMachineId == nil
                ) {
                    self.networkManager.forceReturnToLocal(reason: "menu")
                }

                ForEach(Array(self.networkManager.connectedMachines.enumerated()), id: \.element.id) { index, machine in
                    let shortcut = index < 3 ? "⌃⌥\(index + 2)" : nil
                    let rtt = self.networkManager.peerTelemetry[machine.id]?.rttMs
                    self.deviceRow(
                        title: machine.name,
                        subtitle: machine.mwbPeerID != nil ? "Windows (MWB)" : localizedString("Mac-to-Mac"),
                        systemImage: machine.mwbPeerID != nil ? "pc" : "desktopcomputer",
                        rttMs: rtt,
                        shortcutHint: shortcut,
                        isSelected: activeMachineId == machine.id
                    ) {
                        self.networkManager.requestSwitch(to: machine.id)
                    }
                }
            } else {
                let saved = Array(self.networkManager.savedHosts.hosts.prefix(3))
                if saved.isEmpty {
                    Button {
                        self.openDashboard()
                    } label: {
                        Label(localizedString("Pair a Machine"), systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    ForEach(saved) { host in
                        Button {
                            self.networkManager.compatibilitySettings.protocolMode = host.protocolMode
                            self.networkManager.applyCompatibilitySettings()
                            self.networkManager.connectToHost(ip: host.address, port: host.messagePort)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: host.protocolMode == .mwbCompatibility ? "pc" : "desktopcomputer")
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(host.name)
                                        .font(.caption.weight(.medium))
                                    Text(host.address)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(localizedString("Connect"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func deviceRow(
        title: String,
        subtitle: String,
        systemImage: String,
        rttMs: Int?,
        shortcutHint: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if let rttMs {
                    Text("\(rttMs) ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let shortcutHint {
                    Text(shortcutHint)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func quickControlsGrid() -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            Button {
                self.networkManager.toggleCursorLock()
            } label: {
                Label(
                    self.networkManager.isCursorLocked ? localizedString("Unlock") : localizedString("Lock Screen"),
                    systemImage: self.networkManager.isCursorLocked ? "lock.fill" : "lock.open"
                )
                .font(.caption)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!self.hasConnectedPeers && !self.networkManager.isCursorLocked)
            .help(localizedString("Lock Cursor to Current Screen"))

            Button {
                self.networkManager.toggleInputPause()
            } label: {
                Label(
                    self.networkManager.isInputPaused ? localizedString("Resume") : localizedString("Pause"),
                    systemImage: self.networkManager.isInputPaused ? "play.fill" : "pause.fill"
                )
                .font(.caption)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!self.hasConnectedPeers && !self.networkManager.isInputPaused)
            .help(localizedString("Pause Edge Switching"))

            Button {
                self.networkManager.pushCurrentClipboard()
            } label: {
                Label(localizedString("Clipboard"), systemImage: "doc.on.clipboard")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!self.hasConnectedPeers)
            .help(localizedString("Send Clipboard Now"))

            Button {
                self.networkManager.lockAllScreens()
            } label: {
                Label(localizedString("Lock All"), systemImage: "lock.shield")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!self.hasConnectedPeers)
            .help(localizedString("Lock All Screens"))
        }
    }

    @ViewBuilder
    private func togglesSection(controller: MBAppController, networkManager: MBNetworkManager) -> some View {
        @Bindable var controller = controller
        @Bindable var networkManager = networkManager

        VStack(alignment: .leading, spacing: 6) {
            Toggle(localizedString("Capture Input"), isOn: $controller.captureInput)
                .disabled(!self.accessibilityService.isTrusted)
            Toggle(localizedString("Share Clipboard"), isOn: $networkManager.compatibilitySettings.shareClipboard)
            Toggle(localizedString("Transfer Files"), isOn: $networkManager.compatibilitySettings.transferFiles)
            Toggle(localizedString("Switch by Edge"), isOn: $networkManager.compatibilitySettings.switchByMouse)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.caption)
    }

    @ViewBuilder
    private func footerRow() -> some View {
        HStack {
            Button(localizedString("Open Dashboard...")) {
                self.openDashboard()
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Spacer()

            SettingsLink {
                Label(localizedString("Settings"), systemImage: "gear")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .simultaneousGesture(
                TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                    self.dismiss()
                })

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label(localizedString("Quit"), systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help(localizedString("Quit MagicBorder"))
        }
    }

    private func openDashboard() {
        self.openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        self.dismiss()
    }

    private func statusLine(activeName: String) -> String {
        if !self.accessibilityService.isTrusted {
            return localizedString("Accessibility Permission Needed")
        }
        if !self.hasConnectedPeers {
            return localizedString("No devices connected")
        }
        if self.networkManager.isInputPaused {
            return localizedString("Paused • %@", arguments: [activeName])
        }
        if self.networkManager.isCursorLocked {
            return localizedString("Locked • %@", arguments: [activeName])
        }
        return localizedString("Active: %@", arguments: [activeName])
    }
}
