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

        Button(MBLocalized("Open MagicBorder")) {
            self.openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button(MBLocalized("Machine Arrangement...")) {
            self.openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Text(MBLocalized("Active: %@", arguments: [networkManager.activeMachineName]))
            .font(.caption)

        Menu(MBLocalized("Switch Target")) {
            Button(MBLocalized("Local")) {
                networkManager.activeMachineId = nil
            }
            ForEach(networkManager.connectedMachines) { machine in
                Button(machine.name) {
                    networkManager.requestSwitch(to: machine.id)
                }
            }
        }

        Toggle(MBLocalized("Capture Input"), isOn: self.$captureInput)
            .disabled(!self.accessibilityService.isTrusted)

        Toggle(MBLocalized("Share Clipboard"), isOn: $networkManager.compatibilitySettings.shareClipboard)
        Toggle(MBLocalized("Transfer Files"), isOn: $networkManager.compatibilitySettings.transferFiles)
        Toggle(MBLocalized("Switch by Edge"), isOn: $networkManager.compatibilitySettings.switchByMouse)

        Divider()

        SettingsLink {
            Text(MBLocalized("Settings..."))
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(MBLocalized("Quit MagicBorder")) {
            NSApp.terminate(nil)
        }
    }
}
