import MagicBorderKit
import SwiftUI

struct SettingsView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService
    @AppStorage("wrapMouse") private var wrapMouse = false
    @AppStorage("hideMouse") private var hideMouse = true
    @AppStorage("captureInput") private var captureInput = true
    @AppStorage("dragDropOverlayEnabled") private var dragDropOverlayEnabled = true
    @AppStorage("dragDropOverlayShowDevice") private var dragDropOverlayShowDevice = true
    @AppStorage("dragDropOverlayShowProgress") private var dragDropOverlayShowProgress = true
    @AppStorage("dragDropOverlayScale") private var dragDropOverlayScale = 1.0
    @AppStorage("dragDropOverlayPosition") private var dragDropOverlayPosition = "top"

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
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
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
}

#Preview {
    SettingsView()
        .environment(MagicBorderKit.MBNetworkManager.shared)
}
