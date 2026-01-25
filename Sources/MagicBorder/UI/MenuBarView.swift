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
            self.openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Machine Arrangement...") {
            self.openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
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

        Toggle("Capture Input", isOn: self.$captureInput)
            .disabled(!self.accessibilityService.isTrusted)

        Toggle("Share Clipboard", isOn: $networkManager.compatibilitySettings.shareClipboard)
        Toggle("Transfer Files", isOn: $networkManager.compatibilitySettings.transferFiles)
        Toggle("Switch by Edge", isOn: $networkManager.compatibilitySettings.switchByMouse)

        Divider()

        Button("Quit MagicBorder") {
            NSApp.terminate(nil)
        }
    }
}
