import AppKit
import MagicBorderKit
import SwiftUI

struct MenuBarView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService
    @Environment(\.openWindow) private var openWindow
    @AppStorage("captureInput") private var captureInput = true
    @AppStorage("pairingIPAddress") private var pairingIPAddress: String = ""

    var body: some View {
        @Bindable var networkManager = networkManager

        Button("Open MagicBorder") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Quick Pair...") {
            presentQuickPair()
        }

        Divider()

        Text("Active: \(networkManager.activeMachineName)")
            .font(.caption)

        Menu("Switch Target") {
            Button("Local") {
                networkManager.activeMachineId = nil
            }
            ForEach(networkManager.connectedMachines) { machine in
                Button(machine.name) {
                    networkManager.requestSwitch(to: machine.id)
                }
            }
        }

        Toggle("Capture Input", isOn: $captureInput)
            .disabled(!accessibilityService.isTrusted)

        Toggle("Share Clipboard", isOn: $networkManager.compatibilitySettings.shareClipboard)
        Toggle("Transfer Files", isOn: $networkManager.compatibilitySettings.transferFiles)
        Toggle("Switch by Edge", isOn: $networkManager.compatibilitySettings.switchByMouse)

        Divider()

        Button("Quit MagicBorder") {
            NSApp.terminate(nil)
        }
    }

    private func presentQuickPair() {
        let alert = NSAlert()
        alert.messageText = "Quick Pair"
        alert.informativeText = "Enter the Windows IP to connect."
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")

        let ipField = NSTextField(string: pairingIPAddress)
        ipField.placeholderString = "192.168.1.12"
        ipField.controlSize = .regular

        let keyField = NSTextField(string: networkManager.compatibilitySettings.securityKey)
        keyField.placeholderString = "Security Key"
        keyField.controlSize = .regular

        let stack = NSStackView(views: [ipField, keyField])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        alert.accessoryView = stack

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        pairingIPAddress = ipField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        networkManager.compatibilitySettings.securityKey = keyField.stringValue
        networkManager.applyCompatibilitySettings()
        if !pairingIPAddress.isEmpty {
            networkManager.connectToHost(ip: pairingIPAddress)
        }
    }
}
