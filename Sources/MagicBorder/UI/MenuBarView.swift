import MagicBorderKit
import SwiftUI

struct MenuBarView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService
    @Environment(\.openWindow) private var openWindow
    @AppStorage("captureInput") private var captureInput = true

    var body: some View {
        @Bindable var networkManager = networkManager

        Button("Open MagicBorder") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Text("Active: \(networkManager.activeMachineName)")
            .font(.caption)

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
}
