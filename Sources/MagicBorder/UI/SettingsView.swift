import SwiftUI

struct SettingsView: View {
    @AppStorage("shareClipboard") private var shareClipboard = true
    @AppStorage("transferFiles") private var transferFiles = false
    @AppStorage("wrapMouse") private var wrapMouse = false
    @AppStorage("hideMouse") private var hideMouse = true
    @AppStorage("tcpPort") private var tcpPort = 15100

    var body: some View {
        Form {
            Section(header: Label("Clipboard", systemImage: "clipboard")) {
                Toggle("Share Clipboard", isOn: $shareClipboard)
                Toggle("Transfer Files", isOn: $transferFiles)
            }

            Section(header: Label("Cursor", systemImage: "cursorarrow.motionlines")) {
                Toggle("Wrap Mouse at Screen Edge", isOn: $wrapMouse)
                Toggle("Hide Mouse at Edge", isOn: $hideMouse)
            }

            Section(header: Label("Network", systemImage: "network")) {
                TextField("TCP Port", value: $tcpPort, formatter: NumberFormatter())
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

#Preview {
    SettingsView()
}
