import AppKit
import MagicBorderKit
import SwiftUI

struct InputSettingsTab: View {
    @Environment(MBAppController.self) private var controller
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService
    @State private var showAdvancedEdge = false
    @State private var showCustomizeHotkeys = false

    private var matrixModeBinding: Binding<Int> {
        Binding(
            get: { self.networkManager.compatibilitySettings.matrixOneRow ? 0 : 1 },
            set: { self.networkManager.compatibilitySettings.matrixOneRow = ($0 == 0) })
    }

    var body: some View {
        @Bindable var controller = controller
        @Bindable var networkManager = networkManager

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(localizedString("Cursor Control"))
                        .font(.headline)

                    Toggle(localizedString("Capture Local Input"), isOn: $controller.captureInput)
                        .disabled(!self.accessibilityService.isTrusted)

                    if !self.accessibilityService.isTrusted {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(localizedString("Permission Required"))
                                    .font(.headline)
                                Text(
                                    localizedString(
                                        "MagicBorder needs accessibility access to share mouse and keyboard input.")
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Button(localizedString("Open System Settings")) {
                                    self.accessibilityService.openSystemSettings()
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                    }

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
                    .frame(width: 320)

                    HStack {
                        Text(localizedString("Edge Dwell Delay"))
                        Slider(
                            value: $networkManager.compatibilitySettings.edgeDwellSeconds,
                            in: 0.0...0.5,
                            step: 0.05
                        )
                        .frame(width: 140)
                        Text(
                            "\(Int((networkManager.compatibilitySettings.edgeDwellSeconds * 1000).rounded()))ms"
                        )
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }

                    Toggle(
                        localizedString("Block Corner Switching"),
                        isOn: $networkManager.compatibilitySettings.blockCorners)
                    Toggle(
                        localizedString("Lock Cursor in Fullscreen Apps"),
                        isOn: $networkManager.compatibilitySettings.lockCursorInFullscreenApps)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
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
                    .frame(width: 340)

                    Text(
                        localizedString(
                            "Double-Tap Esc lets single Escape pass through to remote editors and games.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Toggle(
                        localizedString("Enable Global Hotkeys"),
                        isOn: $networkManager.compatibilitySettings.globalHotkeysEnabled)

                    DisclosureGroup(localizedString("Customize Global Hotkeys"), isExpanded: self.$showCustomizeHotkeys)
                    {
                        VStack(alignment: .leading, spacing: 8) {
                            HotkeyRecorderRow(
                                title: localizedString("Lock Cursor to Current Screen"),
                                binding: $networkManager.compatibilitySettings.hotkeys.toggleCursorLock)
                            HotkeyRecorderRow(
                                title: localizedString("Pause Edge Switching"),
                                binding: $networkManager.compatibilitySettings.hotkeys.toggleInputPause)
                            HotkeyRecorderRow(
                                title: localizedString("Lock All Screens"),
                                binding: $networkManager.compatibilitySettings.hotkeys.lockAllScreens)
                            HotkeyRecorderRow(
                                title: localizedString("Switch to Machine 1 (Local)"),
                                binding: $networkManager.compatibilitySettings.hotkeys.slot1)
                            HotkeyRecorderRow(
                                title: localizedString("Switch to Machine 2"),
                                binding: $networkManager.compatibilitySettings.hotkeys.slot2)
                            HotkeyRecorderRow(
                                title: localizedString("Switch to Machine 3"),
                                binding: $networkManager.compatibilitySettings.hotkeys.slot3)
                            HotkeyRecorderRow(
                                title: localizedString("Switch to Machine 4"),
                                binding: $networkManager.compatibilitySettings.hotkeys.slot4)

                            Button(localizedString("Reset Default Hotkeys")) {
                                networkManager.compatibilitySettings.hotkeys = .default
                            }
                            .controlSize(.small)
                            .padding(.top, 4)
                        }
                        .padding(.top, 6)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(localizedString("Mac <-> Windows Comfort"))
                        .font(.headline)

                    Picker(
                        localizedString("Modifier Mapping"),
                        selection: $networkManager.compatibilitySettings.modifierRemapMode
                    ) {
                        Text(localizedString("Standard (Ctrl->Ctrl, Cmd->Win)")).tag(MBModifierRemapMode.standard)
                        Text(localizedString("Mac Shortcuts (Swap Cmd <-> Ctrl)")).tag(
                            MBModifierRemapMode.swapCommandControl)
                    }
                    .frame(width: 360)

                    Toggle(
                        localizedString("Invert Remote Scroll Direction"),
                        isOn: $networkManager.compatibilitySettings.invertRemoteScroll)

                    HStack {
                        Text(localizedString("Remote Scroll Speed"))
                        Slider(
                            value: $networkManager.compatibilitySettings.remoteScrollSpeed,
                            in: 0.25...2.5,
                            step: 0.25
                        )
                        .frame(width: 140)
                        Text("\(networkManager.compatibilitySettings.remoteScrollSpeed, specifier: "%.2fx")")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                DisclosureGroup(localizedString("Advanced Edge & Matrix Options"), isExpanded: self.$showAdvancedEdge) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(localizedString("Edge Switch Lock"))
                            Slider(
                                value: $networkManager.compatibilitySettings.edgeSwitchLockSeconds,
                                in: 0.1...1.0
                            )
                            .frame(width: 120)
                            Text("\(networkManager.compatibilitySettings.edgeSwitchLockSeconds, specifier: "%.2fs")")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text(localizedString("Edge Safe Margin"))
                            Slider(
                                value: $networkManager.compatibilitySettings.edgeSwitchSafeMargin,
                                in: 4...40,
                                step: 2
                            )
                            .frame(width: 120)
                            Text("\(Int(networkManager.compatibilitySettings.edgeSwitchSafeMargin))px")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Toggle(
                            localizedString("Center Cursor on Manual Switch"),
                            isOn: $networkManager.compatibilitySettings.centerCursorOnManualSwitch)
                        Toggle(
                            localizedString("Wrap Mouse at Screen Edge"),
                            isOn: $networkManager.compatibilitySettings.wrapCursor)
                        Toggle(
                            localizedString("Relative Mouse Movement"),
                            isOn: $networkManager.compatibilitySettings.moveMouseRelatively)

                        Picker(localizedString("Layout Mode"), selection: self.matrixModeBinding) {
                            Text(localizedString("Single Row")).tag(0)
                            Text(localizedString("Grid (2 Rows)")).tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)

                        Toggle(
                            localizedString("Cycle Through Screens"),
                            isOn: $networkManager.compatibilitySettings.matrixCircle)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(height: 480)
    }
}

private struct HotkeyRecorderRow: View {
    let title: String
    @Binding var binding: MBHotkeyBinding
    @State private var isRecording = false
    @State private var monitorToken: Any?

    var body: some View {
        HStack {
            Text(self.title)
                .font(.caption)
            Spacer()
            Button {
                self.isRecording ? self.stopRecording() : self.startRecording()
            } label: {
                Text(self.isRecording ? localizedString("Press shortcut...") : self.binding.displayLabel)
                    .font(.caption.monospaced())
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .onDisappear {
            self.stopRecording()
        }
    }

    private func startRecording() {
        self.stopRecording()
        self.isRecording = true
        self.monitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                self.stopRecording()
                return nil
            }
            let cgFlags = Self.cgFlags(from: event.modifierFlags)
            guard !cgFlags.intersection(MBHotkeyBinding.relevantModifierMask).isEmpty else {
                return nil
            }
            self.binding = MBHotkeyBinding(keyCode: Int64(event.keyCode), flags: cgFlags)
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        self.isRecording = false
        if let token = self.monitorToken {
            NSEvent.removeMonitor(token)
            self.monitorToken = nil
        }
    }

    private static func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result = CGEventFlags()
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        return result
    }
}
