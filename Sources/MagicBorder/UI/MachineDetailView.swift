import MagicBorderKit
import SwiftUI

struct MachineDetailView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    let machine: Machine

    @State private var isRefreshing = false

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Section
                VStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue.gradient)
                        .shadow(radius: 2, y: 1)

                    VStack(spacing: 4) {
                        Text(self.machine.name)
                            .font(.title2)
                            .fontWeight(.semibold)

                        HStack(spacing: 6) {
                            StatusDot(active: self.machine.isOnline)
                            Text(
                                self.machine.isOnline
                                    ? String(localized: "Online") : String(localized: "Offline"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Material.regular, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Content
                VStack(alignment: .leading, spacing: 24) {
                    // Pinned Apps
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pinned Apps", comment: "Section header for pinned applications")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: self.columns, spacing: 16) {
                            ForEach(0 ..< 8) { i in
                                ProgramIconButton(name: "App \(i + 1)", icon: "app.dashed")
                            }
                        }
                        .padding(16)
                        .background(
                            Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.1)))
                        .padding(.horizontal)
                    }

                    // Settings
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Settings", comment: "Section header for machine settings")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 0) {
                            NavigationLink {
                                MachineDisplaySettingsView(machine: self.machine)
                            } label: {
                                HStack {
                                    Label("Display Settings", systemImage: "display")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading)

                            NavigationLink {
                                MachineInputSettingsView(machine: self.machine)
                            } label: {
                                HStack {
                                    Label("Input Configuration", systemImage: "keyboard")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .background(
                            Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.1)))
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(self.machine.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    self.isRefreshing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.isRefreshing = false
                    }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .rotationEffect(.degrees(self.isRefreshing ? 360 : 0))
                }
                .disabled(self.isRefreshing)
                .help("Refresh Status")
            }

            ToolbarItem(placement: .status) {
                Button(action: {
                    self.networkManager.reconnect(machineId: self.machine.id)
                }) {
                    Label("Restart Connection", systemImage: "restart")
                }
                .help("Restart Connection")
            }

            ToolbarItem(placement: .destructiveAction) {
                Button(action: {
                    self.networkManager.disconnect(machineId: self.machine.id)
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
                LabeledContent("Name", value: String(localized: "Built-in Retina Display"))
                LabeledContent(
                    "Connection",
                    value: self.machine.isOnline ? "Thunderbolt / IP" : String(localized: "Offline"))
            }

            Section("Settings") {
                Picker("Resolution", selection: self.$resolution) {
                    Text("1920 x 1080").tag("1920 x 1080")
                    Text("2560 x 1440").tag("2560 x 1440")
                    Text("3840 x 2160").tag("3840 x 2160")
                }

                Picker("Refresh Rate", selection: self.$refreshRate) {
                    Text("60 Hz").tag("60 Hz")
                    Text("120 Hz (ProMotion)").tag("120 Hz")
                }

                Toggle("Mirror Main Display", isOn: self.$isMirroring)
            }

            Section("Scaling") {
                VStack(alignment: .leading) {
                    Slider(value: self.$scale, in: 0.5 ... 2.0, step: 0.25) {
                        Text("Display Scale")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                    }
                    Text("Current Scale: \(Int(self.scale * 100))%")
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
                Toggle(isOn: self.$keyboardEnabled) {
                    Label("Share Keyboard", systemImage: "keyboard")
                }
                Toggle(isOn: self.$mouseEnabled) {
                    Label("Share Mouse / Trackpad", systemImage: "mouse")
                }
            }

            Section("Features") {
                Toggle("Clipboard Synchronization", isOn: self.$clipboardSharing)
                Toggle("Global Shortcuts", isOn: self.$shortcutsEnabled)
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

    var body: some View {
        Button(action: {
            // Mock launch
        }) {
            VStack(spacing: 8) {
                Image(systemName: self.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                    .frame(width: 50, height: 50)

                Text(self.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
