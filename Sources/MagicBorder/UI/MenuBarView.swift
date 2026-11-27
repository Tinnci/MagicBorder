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
        @Bindable var sessionCoordinator = networkManager.sessionCoordinator

        Button(localizedString("Open MagicBorder")) {
            self.openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button(localizedString("Machine Arrangement...")) {
            self.openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Text(localizedString("Active: %@", arguments: [sessionCoordinator.activeMachineName]))
            .font(.caption)

        Menu(localizedString("Switch Target")) {
            Button(localizedString("Local")) {
                networkManager.forceReturnToLocal(reason: "menu")
            }
            ForEach(networkManager.connectedMachines) { machine in
                Button(machine.name) {
                    networkManager.requestSwitch(to: machine.id)
                }
            }
        }

        Toggle(localizedString("Capture Input"), isOn: self.$captureInput)
            .disabled(!self.accessibilityService.isTrusted)

        Toggle(localizedString("Share Clipboard"), isOn: $networkManager.compatibilitySettings.shareClipboard)
        Toggle(localizedString("Transfer Files"), isOn: $networkManager.compatibilitySettings.transferFiles)
        Toggle(localizedString("Switch by Edge"), isOn: $networkManager.compatibilitySettings.switchByMouse)

        Divider()

        SettingsLink {
            Text(localizedString("Settings..."))
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(localizedString("Quit MagicBorder")) {
            NSApp.terminate(nil)
        }
    }
}
