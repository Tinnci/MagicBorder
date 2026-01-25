import SwiftUI
import MagicBorderKit

struct SettingsView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @AppStorage("wrapMouse") private var wrapMouse = false
    @AppStorage("hideMouse") private var hideMouse = true

    private var shareClipboardBinding: Binding<Bool> {
        Binding(
            get: { networkManager.compatibilitySettings.shareClipboard },
            set: { networkManager.compatibilitySettings.shareClipboard = $0 }
        )
    }

    private var transferFilesBinding: Binding<Bool> {
        Binding(
            get: { networkManager.compatibilitySettings.transferFiles },
            set: { networkManager.compatibilitySettings.transferFiles = $0 }
        )
    }

    private var messagePortBinding: Binding<UInt16> {
        Binding(
            get: { networkManager.compatibilitySettings.messagePort },
            set: { networkManager.compatibilitySettings.messagePort = $0 }
        )
    }

    private var clipboardPortBinding: Binding<UInt16> {
        Binding(
            get: { networkManager.compatibilitySettings.clipboardPort },
            set: { networkManager.compatibilitySettings.clipboardPort = $0 }
        )
    }

    private var matrixOneRowBinding: Binding<Bool> {
        Binding(
            get: { networkManager.compatibilitySettings.matrixOneRow },
            set: { networkManager.compatibilitySettings.matrixOneRow = $0 }
        )
    }

    private var matrixCircleBinding: Binding<Bool> {
        Binding(
            get: { networkManager.compatibilitySettings.matrixCircle },
            set: { networkManager.compatibilitySettings.matrixCircle = $0 }
        )
    }

    private var securityKeyBinding: Binding<String> {
        Binding(
            get: { networkManager.compatibilitySettings.securityKey },
            set: { networkManager.compatibilitySettings.securityKey = $0 }
        )
    }

    var body: some View {
        Form {
            Section(header: Label("Clipboard", systemImage: "clipboard")) {
                Toggle("Share Clipboard", isOn: shareClipboardBinding)
                Toggle("Transfer Files", isOn: transferFilesBinding)
            }

            Section(header: Label("Cursor", systemImage: "cursorarrow.motionlines")) {
                Toggle("Wrap Mouse at Screen Edge", isOn: $wrapMouse)
                Toggle("Hide Mouse at Edge", isOn: $hideMouse)
            }

            Section(header: Label("Network", systemImage: "network")) {
                TextField("Message Port", value: messagePortBinding, formatter: NumberFormatter())
                TextField("Clipboard Port", value: clipboardPortBinding, formatter: NumberFormatter())
            }

            Section(header: Label("Matrix", systemImage: "square.grid.2x2")) {
                Toggle("Matrix One Row", isOn: matrixOneRowBinding)
                Toggle("Matrix Circle (Swap)", isOn: matrixCircleBinding)
            }

            Section(header: Label("Security", systemImage: "key.fill")) {
                TextField("Security Key", text: securityKeyBinding)
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
