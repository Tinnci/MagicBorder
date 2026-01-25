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
                    Label("Network", systemImage: "network")
                }
                .tag("network")

            OverlaySettingsTab()
                .tabItem {
                    Label("Overlay", systemImage: "display")
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

    var body: some View {
        @Bindable var networkManager = networkManager

        Form {
            Section("Clipboard & Files") {
                Toggle(
                    "Share Clipboard", isOn: $networkManager.compatibilitySettings.shareClipboard)
                Toggle("Transfer Files", isOn: $networkManager.compatibilitySettings.transferFiles)
            }

            Section("Cursor Control") {
                Toggle("Capture Local Input", isOn: $captureInput)
                    .disabled(!accessibilityService.isTrusted)

                if !accessibilityService.isTrusted {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Accessibility permission required")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

                Toggle(
                    "Switch by Moving to Edge",
                    isOn: $networkManager.compatibilitySettings.switchByMouse)
                Toggle(
                    "Block Corner Switching",
                    isOn: $networkManager.compatibilitySettings.blockCorners)
                Toggle("Wrap Mouse at Screen Edge", isOn: $wrapMouse)
                Toggle("Hide Mouse at Edge", isOn: $hideMouse)
                Toggle(
                    "Relative Mouse Movement",
                    isOn: $networkManager.compatibilitySettings.moveMouseRelatively)
            }

            Section("Matrix Configuration") {
                Toggle(
                    "Single Row Matrix", isOn: $networkManager.compatibilitySettings.matrixOneRow)
                Toggle(
                    "Cycle Through Screens",
                    isOn: $networkManager.compatibilitySettings.matrixCircle)
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
                Toggle("Show Overlay", isOn: $dragDropOverlayEnabled)

                Group {
                    Toggle("Show Device Name", isOn: $dragDropOverlayShowDevice)
                    Toggle("Show Progress", isOn: $dragDropOverlayShowProgress)

                    LabeledContent("Size") {
                        HStack {
                            Slider(value: $dragDropOverlayScale, in: 0.85 ... 1.3, step: 0.05)
                            Text("\(Int(dragDropOverlayScale * 100))%")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }

                    Picker("Position", selection: $dragDropOverlayPosition) {
                        Text("Top").tag("top")
                        Text("Bottom").tag("bottom")
                        Text("Top Left").tag("topLeading")
                        Text("Top Right").tag("topTrailing")
                        Text("Bottom Left").tag("bottomLeading")
                        Text("Bottom Right").tag("bottomTrailing")
                    }
                }
                .disabled(!dragDropOverlayEnabled)
            }

            Section("Per-Device Override") {
                Picker("Target Device", selection: $selectedDevice) {
                    ForEach(deviceOptions, id: \.self) { device in
                        Text(device).tag(device)
                    }
                }

                if !selectedDevice.isEmpty {
                    Toggle("Override Global Settings", isOn: useOverrideBinding)

                    if overlayPreferences.hasOverride(for: selectedDevice) {
                        Toggle("Show Device Name", isOn: showDeviceBinding)
                        Toggle("Show Progress", isOn: showProgressBinding)

                        LabeledContent("Size") {
                            HStack {
                                Slider(value: scaleBinding, in: 0.85 ... 1.3, step: 0.05)
                                Text("\(Int(scaleBinding.wrappedValue * 100))%")
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
            if selectedDevice.isEmpty {
                selectedDevice = networkManager.localDisplayName
            }
        }
    }

    // MARK: - Helpers

    private var deviceOptions: [String] {
        let connected = networkManager.connectedMachines.map(\.name)
        let stored = overlayPreferences.allDeviceNames()
        let base = [networkManager.localDisplayName] + connected
        return Array(Set(base + stored)).sorted()
    }

    private var defaultOverlayPreferences: MBOverlayPreferences {
        let position = MBOverlayPosition(rawValue: dragDropOverlayPosition) ?? .top
        return MBOverlayPreferences(
            showDevice: dragDropOverlayShowDevice,
            showProgress: dragDropOverlayShowProgress,
            scale: dragDropOverlayScale,
            position: position)
    }

    private var currentDevicePreferences: MBOverlayPreferences {
        overlayPreferences.preferences(for: selectedDevice, default: defaultOverlayPreferences)
    }

    private var useOverrideBinding: Binding<Bool> {
        Binding(
            get: { overlayPreferences.hasOverride(for: selectedDevice) },
            set: { enabled in
                if enabled {
                    overlayPreferences.setOverride(currentDevicePreferences, for: selectedDevice)
                } else {
                    overlayPreferences.clearOverride(for: selectedDevice)
                }
            })
    }

    private var showDeviceBinding: Binding<Bool> {
        Binding(
            get: { currentDevicePreferences.showDevice },
            set: { val in updateDevicePreferences { $0.showDevice = val } })
    }

    private var showProgressBinding: Binding<Bool> {
        Binding(
            get: { currentDevicePreferences.showProgress },
            set: { val in updateDevicePreferences { $0.showProgress = val } })
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { currentDevicePreferences.scale },
            set: { val in updateDevicePreferences { $0.scale = val } })
    }

    private func updateDevicePreferences(_ update: (inout MBOverlayPreferences) -> Void) {
        var prefs = currentDevicePreferences
        update(&prefs)
        overlayPreferences.setOverride(prefs, for: selectedDevice)
    }
}

#Preview {
    SettingsView()
        .environment(MagicBorderKit.MBNetworkManager.shared)
        .environment(MBAccessibilityService())
        .environment(MBOverlayPreferencesStore())
}
