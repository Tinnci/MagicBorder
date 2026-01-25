import MagicBorderKit
import SwiftUI

struct SettingsView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @AppStorage("wrapMouse") private var wrapMouse = false
    @AppStorage("hideMouse") private var hideMouse = true

    var body: some View {
        @Bindable var networkManager = networkManager

        Form {
            Section(header: Label("Clipboard", systemImage: "clipboard")) {
                Toggle(
                    "Share Clipboard", isOn: $networkManager.compatibilitySettings.shareClipboard)
                Toggle("Transfer Files", isOn: $networkManager.compatibilitySettings.transferFiles)
            }

            Section(header: Label("Cursor", systemImage: "cursorarrow.motionlines")) {
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
