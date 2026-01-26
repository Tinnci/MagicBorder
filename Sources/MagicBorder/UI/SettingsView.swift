import MagicBorderKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("general")

            NetworkSettingsTab()
                .tabItem {
                    Label("Network", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag("network")

            OverlaySettingsTab()
                .tabItem {
                    Label("Overlay", systemImage: "macwindow.on.rectangle")
                }
                .tag("overlay")
        }
        .frame(minWidth: 500, idealWidth: 550, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Tabs

private struct GeneralSettingsTab: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService
    @AppStorage("wrapMouse") private var wrapMouse = false
    @AppStorage("hideMouse") private var hideMouse = true
    @AppStorage("captureInput") private var captureInput = true

    private var matrixModeBinding: Binding<Int> {
        Binding(
            get: { self.networkManager.compatibilitySettings.matrixOneRow ? 0 : 1 },
            set: { self.networkManager.compatibilitySettings.matrixOneRow = ($0 == 0) })
    }

    var body: some View {
        @Bindable var networkManager = networkManager

        Form {
            Section("Clipboard & Files") {
                Toggle(
                    "Share Clipboard", isOn: $networkManager.compatibilitySettings.shareClipboard)
                Toggle("Transfer Files", isOn: $networkManager.compatibilitySettings.transferFiles)
            }

            Section("Cursor Control") {
                Toggle("Capture Local Input", isOn: self.$captureInput)
                    .disabled(!self.accessibilityService.isTrusted)

                if !self.accessibilityService.isTrusted {
                    GroupBox {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Permission Required")
                                    .font(.headline)
                                Text(
                                    "MagicBorder needs accessibility access to share mouse and keyboard input.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Open System Settings") {
                                    self.accessibilityService.openSystemSettings()
                                }
                                .controlSize(.small)
                                .padding(.top, 4)
                            }
                        }
                        .padding(4)
                    }
                    .padding(.vertical, 4)
                }

                Toggle(
                    "Switch by Moving to Edge",
                    isOn: $networkManager.compatibilitySettings.switchByMouse)
                Toggle(
                    "Block Corner Switching",
                    isOn: $networkManager.compatibilitySettings.blockCorners)
                Toggle(
                    "Center Cursor on Manual Switch",
                    isOn: $networkManager.compatibilitySettings.centerCursorOnManualSwitch)
                LabeledContent("Edge Switch Lock") {
                    HStack {
                        Slider(
                            value: $networkManager.compatibilitySettings.edgeSwitchLockSeconds,
                            in: 0.1 ... 1.0,
                            step: 0.05)
                        Text(
                            "\(networkManager.compatibilitySettings.edgeSwitchLockSeconds, specifier: "%.2fs")")
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                }
                LabeledContent("Edge Safe Margin") {
                    HStack {
                        Slider(
                            value: $networkManager.compatibilitySettings.edgeSwitchSafeMargin,
                            in: 4 ... 40,
                            step: 2)
                        Text(
                            "\(Int(networkManager.compatibilitySettings.edgeSwitchSafeMargin))px")
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                }
                Toggle("Wrap Mouse at Screen Edge", isOn: self.$wrapMouse)
                Toggle("Hide Mouse at Edge", isOn: self.$hideMouse)
                Toggle(
                    "Relative Mouse Movement",
                    isOn: $networkManager.compatibilitySettings.moveMouseRelatively)
            }

            Section {
                Picker("Layout Mode", selection: self.matrixModeBinding) {
                    Label("Single Row", systemImage: "rectangle.grid.1x2").tag(0)
                    Label("Grid (2 Rows)", systemImage: "square.grid.2x2").tag(1)
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Toggle(
                    "Cycle Through Screens",
                    isOn: $networkManager.compatibilitySettings.matrixCircle)
            } header: {
                Text("Matrix Configuration")
            } footer: {
                if networkManager.compatibilitySettings.matrixOneRow {
                    Text("Machines are arranged in a single horizontal line.")
                } else {
                    Text("Machines are arranged in a 2-row grid layout.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct NetworkSettingsTab: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager

    var body: some View {
        @Bindable var networkManager = networkManager

        Form {
            Section("Security") {
                VStack(alignment: .leading) {
                    SecureField(
                        "Security Key", text: $networkManager.compatibilitySettings.securityKey)
                        .textContentType(.password)
                        .frame(maxWidth: 300)

                    if let message = networkManager.compatibilitySettings.validationMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(message.contains("Success") ? .green : .red)
                    }
                }

                Button("Validate Key") {
                    _ = networkManager.compatibilitySettings.validateSecurityKey()
                }
            }

            Section("Ports") {
                HStack {
                    TextField(
                        "Message Port", value: $networkManager.compatibilitySettings.messagePort,
                        formatter: NumberFormatter())
                        .monospacedDigit()
                    Text("Default: 20000").font(.caption).foregroundStyle(.secondary)
                }

                HStack {
                    TextField(
                        "Clipboard Port",
                        value: $networkManager.compatibilitySettings.clipboardPort,
                        formatter: NumberFormatter())
                        .monospacedDigit()
                    Text("Default: 20001").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct OverlaySettingsTab: View {
    @Environment(MBOverlayPreferencesStore.self) private var overlayPreferences
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager

    @AppStorage("dragDropOverlayEnabled") private var dragDropOverlayEnabled = true
    @AppStorage("dragDropOverlayShowDevice") private var dragDropOverlayShowDevice = true
    @AppStorage("dragDropOverlayShowProgress") private var dragDropOverlayShowProgress = true
    @AppStorage("dragDropOverlayScale") private var dragDropOverlayScale = 1.0
    @AppStorage("dragDropOverlayPosition") private var dragDropOverlayPosition = "top"

    @State private var selectedDevice: String = ""

    var body: some View {
        Form {
            Section("Global Defaults") {
                Toggle("Show Overlay", isOn: self.$dragDropOverlayEnabled)

                Group {
                    Toggle("Show Device Name", isOn: self.$dragDropOverlayShowDevice)
                    Toggle("Show Progress", isOn: self.$dragDropOverlayShowProgress)

                    LabeledContent("Size") {
                        HStack {
                            Slider(value: self.$dragDropOverlayScale, in: 0.85 ... 1.3, step: 0.05)
                            Text("\(Int(self.dragDropOverlayScale * 100))%")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }

                    Picker("Position", selection: self.$dragDropOverlayPosition) {
                        Text("Top").tag("top")
                        Text("Bottom").tag("bottom")
                        Text("Top Left").tag("topLeading")
                        Text("Top Right").tag("topTrailing")
                        Text("Bottom Left").tag("bottomLeading")
                        Text("Bottom Right").tag("bottomTrailing")
                    }
                }
                .disabled(!self.dragDropOverlayEnabled)
            }

            Section("Per-Device Override") {
                Picker("Target Device", selection: self.$selectedDevice) {
                    ForEach(self.deviceOptions, id: \.self) { device in
                        Text(device).tag(device)
                    }
                }

                if !self.selectedDevice.isEmpty {
                    Toggle("Override Global Settings", isOn: self.useOverrideBinding)

                    if self.overlayPreferences.hasOverride(for: self.selectedDevice) {
                        Toggle("Show Device Name", isOn: self.showDeviceBinding)
                        Toggle("Show Progress", isOn: self.showProgressBinding)

                        LabeledContent("Size") {
                            HStack {
                                Slider(value: self.scaleBinding, in: 0.85 ... 1.3, step: 0.05)
                                Text("\(Int(self.scaleBinding.wrappedValue * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if self.selectedDevice.isEmpty {
                self.selectedDevice = self.networkManager.localDisplayName
            }
        }
    }

    // MARK: - Helpers

    private var deviceOptions: [String] {
        let connected = self.networkManager.connectedMachines.map(\.name)
        let stored = self.overlayPreferences.allDeviceNames()
        let base = [networkManager.localDisplayName] + connected
        return Array(Set(base + stored)).sorted()
    }

    private var defaultOverlayPreferences: MBOverlayPreferences {
        let position = MBOverlayPosition(rawValue: dragDropOverlayPosition) ?? .top
        return MBOverlayPreferences(
            showDevice: self.dragDropOverlayShowDevice,
            showProgress: self.dragDropOverlayShowProgress,
            scale: self.dragDropOverlayScale,
            position: position)
    }

    private var currentDevicePreferences: MBOverlayPreferences {
        self.overlayPreferences.preferences(
            for: self.selectedDevice, default: self.defaultOverlayPreferences)
    }

    private var useOverrideBinding: Binding<Bool> {
        Binding(
            get: { self.overlayPreferences.hasOverride(for: self.selectedDevice) },
            set: { enabled in
                if enabled {
                    self.overlayPreferences.setOverride(
                        self.currentDevicePreferences, for: self.selectedDevice)
                } else {
                    self.overlayPreferences.clearOverride(for: self.selectedDevice)
                }
            })
    }

    private var showDeviceBinding: Binding<Bool> {
        Binding(
            get: { self.currentDevicePreferences.showDevice },
            set: { val in self.updateDevicePreferences { $0.showDevice = val } })
    }

    private var showProgressBinding: Binding<Bool> {
        Binding(
            get: { self.currentDevicePreferences.showProgress },
            set: { val in self.updateDevicePreferences { $0.showProgress = val } })
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { self.currentDevicePreferences.scale },
            set: { val in self.updateDevicePreferences { $0.scale = val } })
    }

    private func updateDevicePreferences(_ update: (inout MBOverlayPreferences) -> Void) {
        var prefs = self.currentDevicePreferences
        update(&prefs)
        self.overlayPreferences.setOverride(prefs, for: self.selectedDevice)
    }
}

#Preview {
    SettingsView()
        .environment(MagicBorderKit.MBNetworkManager.shared)
        .environment(MBAccessibilityService())
        .environment(MBOverlayPreferencesStore())
}
