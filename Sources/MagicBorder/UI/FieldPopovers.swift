import MagicBorderKit
import SwiftUI

struct EdgeBehaviorPopover: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @State private var showAdvanced = false

    private var twoRowBinding: Binding<Bool> {
        Binding(
            get: { !self.networkManager.compatibilitySettings.matrixOneRow },
            set: { self.networkManager.compatibilitySettings.matrixOneRow = !$0 })
    }

    var body: some View {
        @Bindable var networkManager = self.networkManager

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(localizedString("Edge & Border Rules"))
                    .font(.headline)

                Toggle(
                    localizedString("Switch by Moving to Edge"),
                    isOn: $networkManager.compatibilitySettings.switchByMouse)

                Picker(
                    localizedString("Modifier to Cross Edge"),
                    selection: $networkManager.compatibilitySettings.edgeCrossingModifier
                ) {
                    Text(localizedString("None (Free Crossing)")).tag(MBEdgeCrossingModifier.none)
                    Text("Command (⌘)").tag(MBEdgeCrossingModifier.command)
                    Text("Option (⌥)").tag(MBEdgeCrossingModifier.option)
                    Text("Control (⌃)").tag(MBEdgeCrossingModifier.control)
                }

                HStack {
                    Text(localizedString("Edge Dwell Delay"))
                    Slider(
                        value: $networkManager.compatibilitySettings.edgeDwellSeconds,
                        in: 0.0...0.5,
                        step: 0.05)
                    Text("\(Int((networkManager.compatibilitySettings.edgeDwellSeconds * 1000).rounded()))ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                }

                Toggle(
                    localizedString("Block Corner Switching"),
                    isOn: $networkManager.compatibilitySettings.blockCorners)
                Toggle(
                    localizedString("Lock Cursor in Fullscreen Apps"),
                    isOn: $networkManager.compatibilitySettings.lockCursorInFullscreenApps)

                Divider()

                Toggle(localizedString("Two Row Matrix"), isOn: self.twoRowBinding)
                Toggle(
                    localizedString("Cycle Through Screens"),
                    isOn: $networkManager.compatibilitySettings.matrixCircle)

                DisclosureGroup(localizedString("Advanced Edge & Matrix Options"), isExpanded: self.$showAdvanced) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(localizedString("Edge Switch Lock"))
                                .font(.caption)
                            Slider(value: $networkManager.compatibilitySettings.edgeSwitchLockSeconds, in: 0.1...1.0)
                            Text("\(networkManager.compatibilitySettings.edgeSwitchLockSeconds, specifier: "%.2fs")")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text(localizedString("Edge Safe Margin"))
                                .font(.caption)
                            Slider(
                                value: $networkManager.compatibilitySettings.edgeSwitchSafeMargin,
                                in: 4...40,
                                step: 2)
                            Text("\(Int(networkManager.compatibilitySettings.edgeSwitchSafeMargin))px")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Toggle(
                            localizedString("Wrap Mouse at Screen Edge"),
                            isOn: $networkManager.compatibilitySettings.wrapCursor
                        )
                        .font(.caption)
                        Toggle(
                            localizedString("Center Cursor on Manual Switch"),
                            isOn: $networkManager.compatibilitySettings.centerCursorOnManualSwitch
                        )
                        .font(.caption)
                        Toggle(
                            localizedString("Relative Mouse Movement"),
                            isOn: $networkManager.compatibilitySettings.moveMouseRelatively
                        )
                        .font(.caption)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(16)
        }
        .frame(width: 340)
        .frame(maxHeight: 460)
    }
}

struct ProtocolAndPairingPopover: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager

    var body: some View {
        @Bindable var networkManager = self.networkManager

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedString("Protocol Mode"))
                        .font(.headline)

                    Picker(
                        localizedString("Protocol Mode"),
                        selection: $networkManager.compatibilitySettings.protocolMode
                    ) {
                        Text(localizedString("Windows (MWB)")).tag(MBProtocolMode.mwbCompatibility)
                        Text(localizedString("Mac-to-Mac")).tag(MBProtocolMode.modern)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Divider()

                PairingFlowView(securityKey: $networkManager.compatibilitySettings.securityKey)
            }
            .padding(16)
        }
        .frame(width: 360)
        .frame(maxHeight: 520)
    }
}

struct ClipboardQuickPopover: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager

    var body: some View {
        @Bindable var networkManager = self.networkManager

        VStack(alignment: .leading, spacing: 12) {
            Text(localizedString("Clipboard & Privacy"))
                .font(.headline)

            Toggle(localizedString("Share Clipboard"), isOn: $networkManager.compatibilitySettings.shareClipboard)
            Toggle(localizedString("Transfer Files"), isOn: $networkManager.compatibilitySettings.transferFiles)
            Toggle(
                localizedString("Ignore Password Manager Items"),
                isOn: $networkManager.compatibilitySettings.ignoreConcealedClipboard)

            HStack {
                Text(localizedString("Max Clipboard Size"))
                Spacer()
                Picker("", selection: $networkManager.compatibilitySettings.maxClipboardSizeMB) {
                    Text("2 MB").tag(2)
                    Text("5 MB").tag(5)
                    Text("10 MB").tag(10)
                    Text("25 MB").tag(25)
                }
                .labelsHidden()
                .frame(width: 96)
            }

            Divider()

            Button {
                self.networkManager.pushCurrentClipboard()
            } label: {
                Label(localizedString("Send Clipboard Now"), systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(self.networkManager.connectedMachines.isEmpty)
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct EscapeQuickPopover: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager

    var body: some View {
        @Bindable var networkManager = self.networkManager

        VStack(alignment: .leading, spacing: 12) {
            Text(localizedString("Escape & Global Hotkeys"))
                .font(.headline)

            Picker(
                localizedString("Return to Local Key"),
                selection: $networkManager.compatibilitySettings.escapeMode
            ) {
                Text(localizedString("Double-Tap Esc (Recommended)")).tag(MBEscapeMode.doubleTapEsc)
                Text("⌃⌥Esc").tag(MBEscapeMode.controlOptionEsc)
                Text(localizedString("Single Esc")).tag(MBEscapeMode.singleEsc)
            }

            Toggle(
                localizedString("Enable Global Hotkeys"),
                isOn: $networkManager.compatibilitySettings.globalHotkeysEnabled)

            let hotkeys = self.networkManager.compatibilitySettings.hotkeys
            VStack(alignment: .leading, spacing: 4) {
                self.shortcutRow(localizedString("Lock Screen"), shortcut: hotkeys.toggleCursorLock.displayLabel)
                self.shortcutRow(localizedString("Pause"), shortcut: hotkeys.toggleInputPause.displayLabel)
                self.shortcutRow(localizedString("Lock All"), shortcut: hotkeys.lockAllScreens.displayLabel)
            }
            .padding(8)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

            SettingsLink {
                Label(localizedString("Customize Hotkeys..."), systemImage: "keyboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 320)
    }

    private func shortcutRow(_ title: String, shortcut: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(shortcut)
                .font(.caption.monospaced())
        }
    }
}
