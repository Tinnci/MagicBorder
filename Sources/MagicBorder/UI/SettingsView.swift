import MagicBorderKit
import SwiftUI

struct SettingsView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService
    @Environment(MBOverlayPreferencesStore.self) private var overlayPreferences
    @AppStorage("wrapMouse") private var wrapMouse = false
    @AppStorage("hideMouse") private var hideMouse = true
    @AppStorage("captureInput") private var captureInput = true
    @AppStorage("dragDropOverlayEnabled") private var dragDropOverlayEnabled = true
    @AppStorage("dragDropOverlayShowDevice") private var dragDropOverlayShowDevice = true
    @AppStorage("dragDropOverlayShowProgress") private var dragDropOverlayShowProgress = true
    @AppStorage("dragDropOverlayScale") private var dragDropOverlayScale = 1.0
    @AppStorage("dragDropOverlayPosition") private var dragDropOverlayPosition = "top"
    @State private var selectedDevice: String = ""

    var body: some View {
        @Bindable var networkManager = networkManager

        Form {
            Section(header: Label("Clipboard", systemImage: "clipboard")) {
                Toggle(
                    "Share Clipboard", isOn: $networkManager.compatibilitySettings.shareClipboard)
                Toggle("Transfer Files", isOn: $networkManager.compatibilitySettings.transferFiles)
            }

            Section(header: Label("Cursor", systemImage: "cursorarrow.motionlines")) {
                Toggle("Capture Local Input", isOn: $captureInput)
                    .disabled(!accessibilityService.isTrusted)
                if !accessibilityService.isTrusted {
                    Text("Enable Accessibility permission to capture input.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Switch by Moving to Edge", isOn: $networkManager.compatibilitySettings.switchByMouse)
                Toggle("Block Corner Switching", isOn: $networkManager.compatibilitySettings.blockCorners)
                Toggle("Wrap Mouse at Screen Edge", isOn: $wrapMouse)
                Toggle("Hide Mouse at Edge", isOn: $hideMouse)
            }

            Section(header: Label("Network", systemImage: "network")) {
                TextField(
                    "Message Port", value: $networkManager.compatibilitySettings.messagePort,
                    formatter: NumberFormatter())
                TextField(
                    "Clipboard Port", value: $networkManager.compatibilitySettings.clipboardPort,
                    formatter: NumberFormatter())
            }

            Section(header: Label("Matrix", systemImage: "square.grid.2x2")) {
                Toggle("Matrix One Row", isOn: $networkManager.compatibilitySettings.matrixOneRow)
                Toggle(
                    "Matrix Circle (Swap)", isOn: $networkManager.compatibilitySettings.matrixCircle
                )
                Toggle("Relative Mouse Movement", isOn: $networkManager.compatibilitySettings.moveMouseRelatively)
            }

            Section(header: Label("Security", systemImage: "key.fill")) {
                TextField("Security Key", text: $networkManager.compatibilitySettings.securityKey)
                if let message = networkManager.compatibilitySettings.validationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Validate Key") {
                    _ = networkManager.compatibilitySettings.validateSecurityKey()
                }
            }

            Section(header: Label("Drag & Drop Overlay", systemImage: "tray.and.arrow.down")) {
                Toggle("Show Overlay", isOn: $dragDropOverlayEnabled)
                Toggle("Show Device Name", isOn: $dragDropOverlayShowDevice)
                    .disabled(!dragDropOverlayEnabled)
                Toggle("Show Progress", isOn: $dragDropOverlayShowProgress)
                    .disabled(!dragDropOverlayEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Overlay Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $dragDropOverlayScale, in: 0.85...1.3, step: 0.05)
                        .disabled(!dragDropOverlayEnabled)
                }

                Picker("Position", selection: $dragDropOverlayPosition) {
                    Text("Top").tag("top")
                    Text("Top Left").tag("topLeading")
                    Text("Top Right").tag("topTrailing")
                    Text("Bottom").tag("bottom")
                    Text("Bottom Left").tag("bottomLeading")
                    Text("Bottom Right").tag("bottomTrailing")
                }
                .pickerStyle(.segmented)
                .disabled(!dragDropOverlayEnabled)
            }

            Section(header: Label("Drag & Drop Overlay (Per Device)", systemImage: "display")) {
                Picker("Device", selection: $selectedDevice) {
                    ForEach(deviceOptions, id: \.self) { device in
                        Text(device).tag(device)
                    }
                }

                Toggle("Use Custom Settings", isOn: useOverrideBinding)
                    .disabled(selectedDevice.isEmpty)

                Toggle("Show Device Name", isOn: showDeviceBinding)
                    .disabled(!overlayPreferences.hasOverride(for: selectedDevice))
                Toggle("Show Progress", isOn: showProgressBinding)
                    .disabled(!overlayPreferences.hasOverride(for: selectedDevice))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Overlay Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: scaleBinding, in: 0.85...1.3, step: 0.05)
                        .disabled(!overlayPreferences.hasOverride(for: selectedDevice))
                }

                Picker("Position", selection: positionBinding) {
                    Text("Top").tag(MBOverlayPosition.top)
                    Text("Top Left").tag(MBOverlayPosition.topLeading)
                    Text("Top Right").tag(MBOverlayPosition.topTrailing)
                    Text("Bottom").tag(MBOverlayPosition.bottom)
                    Text("Bottom Left").tag(MBOverlayPosition.bottomLeading)
                    Text("Bottom Right").tag(MBOverlayPosition.bottomTrailing)
                }
                .pickerStyle(.segmented)
                .disabled(!overlayPreferences.hasOverride(for: selectedDevice))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            if selectedDevice.isEmpty {
                selectedDevice = networkManager.localDisplayName
            }
        }
        .onChange(of: networkManager.compatibilitySettings.securityKey) { _, _ in
            networkManager.applyCompatibilitySettings()
        }
        .onChange(of: networkManager.compatibilitySettings.messagePort) { _, _ in
            networkManager.applyCompatibilitySettings()
        }
        .onChange(of: networkManager.compatibilitySettings.clipboardPort) { _, _ in
            networkManager.applyCompatibilitySettings()
        }
    }

    private var deviceOptions: [String] {
        let connected = networkManager.connectedMachines.map { $0.name }
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
            position: position
        )
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
            }
        )
    }

    private var showDeviceBinding: Binding<Bool> {
        Binding(
            get: { currentDevicePreferences.showDevice },
            set: { newValue in
                updateDevicePreferences { $0.showDevice = newValue }
            }
        )
    }

    private var showProgressBinding: Binding<Bool> {
        Binding(
            get: { currentDevicePreferences.showProgress },
            set: { newValue in
                updateDevicePreferences { $0.showProgress = newValue }
            }
        )
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { currentDevicePreferences.scale },
            set: { newValue in
                updateDevicePreferences { $0.scale = newValue }
            }
        )
    }

    private var positionBinding: Binding<MBOverlayPosition> {
        Binding(
            get: { currentDevicePreferences.position },
            set: { newValue in
                updateDevicePreferences { $0.position = newValue }
            }
        )
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
}
