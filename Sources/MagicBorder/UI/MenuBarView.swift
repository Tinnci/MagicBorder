import AppKit
import MagicBorderKit
import SwiftUI

struct MenuBarView: View {
    @Environment(MBAppController.self) private var controller
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var controller = controller
        @Bindable var networkManager = networkManager
        @Bindable var sessionCoordinator = networkManager.sessionCoordinator

        Button(localizedString("Open Dashboard...")) {
            self.openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Text(self.statusLine(activeName: sessionCoordinator.activeMachineName))
            .font(.caption)

        Menu(localizedString("Switch Target")) {
            Button {
                networkManager.forceReturnToLocal(reason: "menu")
            } label: {
                if sessionCoordinator.activeMachineId == nil {
                    Label(localizedString("Local"), systemImage: "checkmark")
                } else {
                    Text(localizedString("Local"))
                }
            }
            ForEach(Array(networkManager.connectedMachines.enumerated()), id: \.element.id) { index, machine in
                Button {
                    networkManager.requestSwitch(to: machine.id)
                } label: {
                    let title = index < 3 ? "\(machine.name)  ⌃⌥\(index + 2)" : machine.name
                    if sessionCoordinator.activeMachineId == machine.id {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        }

        Button(
            networkManager.isCursorLocked
                ? localizedString("Unlock Cursor from Screen")
                : localizedString("Lock Cursor to Current Screen")
        ) {
            networkManager.toggleCursorLock()
        }

        Button(
            networkManager.isInputPaused
                ? localizedString("Resume Edge Switching")
                : localizedString("Pause Edge Switching")
        ) {
            networkManager.toggleInputPause()
        }

        Button(localizedString("Send Clipboard Now")) {
            networkManager.pushCurrentClipboard()
        }
        .disabled(networkManager.connectedMachines.isEmpty)

        Divider()

        Toggle(localizedString("Capture Input"), isOn: $controller.captureInput)
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

    private func statusLine(activeName: String) -> String {
        if !self.accessibilityService.isTrusted {
            return localizedString("Accessibility Permission Needed")
        }
        if self.networkManager.isInputPaused {
            return localizedString("Paused • %@", arguments: [activeName])
        }
        if self.networkManager.isCursorLocked {
            return localizedString("Locked • %@", arguments: [activeName])
        }
        return localizedString("Active: %@", arguments: [activeName])
    }
}
