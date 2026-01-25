import MagicBorderKit
import SwiftUI

struct MachineDetailView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    let machine: Machine

    @State private var isRefreshing = false

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 16)
    ]

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "desktopcomputer")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(machine.name)
                            .font(.title2)
                            .fontWeight(.medium)
                        HStack(spacing: 6) {
                            StatusDot(active: machine.isOnline)
                            Text(machine.isOnline ? "Online" : "Offline")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section("Pinned Programs") {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<8) { i in
                        ProgramIconButton(name: "App \(i+1)", icon: "app.dashed")
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Configuration") {
                NavigationLink {
                    MachineDisplaySettingsView(machine: machine)
                } label: {
                    Label("Display Settings", systemImage: "display")
                }

                NavigationLink {
                    MachineInputSettingsView(machine: machine)
                } label: {
                    Label("Input Configuration", systemImage: "keyboard")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(machine.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    isRefreshing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        isRefreshing = false
                    }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                }
                .disabled(isRefreshing)
                .help("Refresh Status")
            }

            ToolbarItem(placement: .status) {
                Button(action: {
                    networkManager.reconnect(machineId: machine.id)
                }) {
                    Label("Restart Connection", systemImage: "restart")
                }
                .help("Restart Connection")
            }

            ToolbarItem(placement: .destructiveAction) {
                Button(action: {
                    networkManager.disconnect(machineId: machine.id)
                }) {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .help("Disconnect Machine")
            }
        }
    }
}

// MARK: - Subviews

private struct MachineDisplaySettingsView: View {
    let machine: Machine
    @State private var resolution = "1920 x 1080"
    @State private var scale = 1.0
    @State private var refreshRate = "60 Hz"
    @State private var isMirroring = false

    var body: some View {
        Form {
            Section("Display Info") {
                LabeledContent("Name", value: "Built-in Retina Display")
                LabeledContent(
                    "Connection", value: machine.isOnline ? "Thunderbolt / IP" : "Offline")
            }

            Section("Settings") {
                Picker("Resolution", selection: $resolution) {
                    Text("1920 x 1080").tag("1920 x 1080")
                    Text("2560 x 1440").tag("2560 x 1440")
                    Text("3840 x 2160").tag("3840 x 2160")
                }

                Picker("Refresh Rate", selection: $refreshRate) {
                    Text("60 Hz").tag("60 Hz")
                    Text("120 Hz (ProMotion)").tag("120 Hz")
                }

                Toggle("Mirror Main Display", isOn: $isMirroring)
            }

            Section("Scaling") {
                VStack(alignment: .leading) {
                    Slider(value: $scale, in: 0.5...2.0, step: 0.25) {
                        Text("Display Scale")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                    }
                    Text("Current Scale: \(Int(scale * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Display Settings")
    }
}

private struct MachineInputSettingsView: View {
    let machine: Machine
    @State private var keyboardEnabled = true
    @State private var mouseEnabled = true
    @State private var clipboardSharing = true
    @State private var shortcutsEnabled = true

    var body: some View {
        Form {
            Section("Input Devices") {
                Toggle(isOn: $keyboardEnabled) {
                    Label("Share Keyboard", systemImage: "keyboard")
                }
                Toggle(isOn: $mouseEnabled) {
                    Label("Share Mouse / Trackpad", systemImage: "mouse")
                }
            }

            Section("Features") {
                Toggle("Clipboard Synchronization", isOn: $clipboardSharing)
                Toggle("Global Shortcuts", isOn: $shortcutsEnabled)
            }

            Section("Shortcut Mapping") {
                LabeledContent("Switch Screen") {
                    Text("⌃ ⌥ →")
                        .monospaced()
                        .padding(4)
                        .background(.tertiary, in: RoundedRectangle(cornerRadius: 6))
                }
                LabeledContent("Lock Remote") {
                    Text("⌘ L")
                        .monospaced()
                        .padding(4)
                        .background(.tertiary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Input Configuration")
    }
}

struct ProgramIconButton: View {
    let name: String
    let icon: String

    @State private var isHovering = false

    var body: some View {
        Button(action: {
            // Mock launch
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                    .frame(width: 50, height: 50)

                Text(name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ProgramIconButtonStyle())
    }
}

struct ProgramIconButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onHover { isHovering = $0 }
    }
}
