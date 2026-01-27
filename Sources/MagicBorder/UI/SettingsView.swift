import MagicBorderKit
import SwiftUI

struct SettingsView: View {
    private let width: CGFloat = 500

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label(MBLocalized("General"), systemImage: "gear")
                }
                .frame(width: self.width)
            // Remove explicit padding here as TabView content usually needs its own padding
            // But generally, we want some padding inside the tab content.

            NetworkSettingsTab()
                .tabItem {
                    Label(MBLocalized("Network"), systemImage: "antenna.radiowaves.left.and.right")
                }
                .frame(width: self.width)

            OverlaySettingsTab()
                .tabItem {
                    Label(MBLocalized("Overlay"), systemImage: "macwindow.on.rectangle")
                }
                .frame(width: self.width)
        }
        .padding(20) // Global padding for visually pleasing layout
    }
}

// MARK: - Components

/// A container that mimics a Form Section but calculates its own height
private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(self.title)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                self.content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Tabs

private struct GeneralSettingsTab: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService
    @AppStorage("wrapMouse") private var wrapMouse = false
    @AppStorage("hideMouse") private var hideMouse = true
    @AppStorage("captureInput") private var captureInput = true

    private var matrixModeBinding: Binding<Int> {
        Binding(
            get: { self.networkManager.compatibilitySettings.matrixOneRow ? 0 : 1 },
            set: { self.networkManager.compatibilitySettings.matrixOneRow = ($0 == 0) })
    }

    var body: some View {
        @Bindable var networkManager = networkManager

        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(MBLocalized("Clipboard & Files")) {
                Toggle(
                    MBLocalized("Share Clipboard"),
                    isOn: $networkManager.compatibilitySettings.shareClipboard)
                Toggle(
                    MBLocalized("Transfer Files"),
                    isOn: $networkManager.compatibilitySettings.transferFiles)
            }

            Divider()

            SettingsSection(MBLocalized("Cursor Control")) {
                Toggle(MBLocalized("Capture Local Input"), isOn: self.$captureInput)
                    .disabled(!self.accessibilityService.isTrusted)

                if !self.accessibilityService.isTrusted {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(MBLocalized("Permission Required"))
                                .font(.headline)
                            Text(
                                MBLocalized("MagicBorder needs accessibility access to share mouse and keyboard input."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(MBLocalized("Open System Settings")) {
                                self.accessibilityService.openSystemSettings()
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                }

                Toggle(
                    MBLocalized("Switch by Moving to Edge"),
                    isOn: $networkManager.compatibilitySettings.switchByMouse)
                Toggle(
                    MBLocalized("Block Corner Switching"),
                    isOn: $networkManager.compatibilitySettings.blockCorners)
                Toggle(
                    MBLocalized("Center Cursor on Manual Switch"),
                    isOn: $networkManager.compatibilitySettings.centerCursorOnManualSwitch)

                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text(MBLocalized("Edge Switch Lock"))
                        HStack {
                            Slider(
                                value: $networkManager.compatibilitySettings.edgeSwitchLockSeconds,
                                in: 0.1 ... 1.0)
                                .frame(width: 120)
                            Text(
                                "\(networkManager.compatibilitySettings.edgeSwitchLockSeconds, specifier: "%.2fs")")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text(MBLocalized("Edge Safe Margin"))
                        HStack {
                            Slider(
                                value: $networkManager.compatibilitySettings.edgeSwitchSafeMargin,
                                in: 4 ... 40, step: 2)
                                .frame(width: 120)
                            Text(
                                "\(Int(networkManager.compatibilitySettings.edgeSwitchSafeMargin))px")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 24) // Indent controls slightly

                Toggle(MBLocalized("Wrap Mouse at Screen Edge"), isOn: self.$wrapMouse)
                Toggle(MBLocalized("Hide Mouse at Edge"), isOn: self.$hideMouse)
                Toggle(
                    MBLocalized("Relative Mouse Movement"),
                    isOn: $networkManager.compatibilitySettings.moveMouseRelatively)
            }

            Divider()

            SettingsSection(MBLocalized("Matrix Configuration")) {
                Picker(MBLocalized("Layout Mode"), selection: self.matrixModeBinding) {
                    Text(MBLocalized("Single Row")).tag(0)
                    Text(MBLocalized("Grid (2 Rows)")).tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden() // Segmented picker shows labels inside
                .frame(width: 250)

                Toggle(
                    MBLocalized("Cycle Through Screens"),
                    isOn: $networkManager.compatibilitySettings.matrixCircle)

                Text(
                    networkManager.compatibilitySettings.matrixOneRow
                        ? MBLocalized("Machines are arranged in a single horizontal line.")
                        : MBLocalized("Machines are arranged in a 2-row grid layout."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // .padding() // Padding is handled by parent TabView modifier
    }
}

private struct NetworkSettingsTab: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager

    var body: some View {
        @Bindable var networkManager = networkManager

        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(MBLocalized("Security")) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        SecureField(
                            MBLocalized("Security Key"),
                            text: $networkManager.compatibilitySettings.securityKey)
                            .textContentType(.password)
                            .frame(width: 240)

                        if let message = networkManager.compatibilitySettings.validationMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(message.contains("Success") ? .green : .red)
                        }
                    }

                    Button(MBLocalized("Validate")) {
                        _ = networkManager.compatibilitySettings.validateSecurityKey()
                    }
                }
            }

            Divider()

            SettingsSection(MBLocalized("Ports")) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text(MBLocalized("Message Port"))
                        TextField(
                            MBLocalized("20000"),
                            value: $networkManager.compatibilitySettings.messagePort,
                            formatter: NumberFormatter())
                            .monospacedDigit()
                            .frame(width: 80)
                        Text(MBLocalized("Default: 20000"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text(MBLocalized("Clipboard Port"))
                        TextField(
                            MBLocalized("20001"),
                            value: $networkManager.compatibilitySettings.clipboardPort,
                            formatter: NumberFormatter())
                            .monospacedDigit()
                            .frame(width: 80)
                        Text(MBLocalized("Default: 20001"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct OverlaySettingsTab: View {
    @Environment(MBOverlayPreferencesStore.self) private var overlayPreferences
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager

    @AppStorage("dragDropOverlayEnabled") private var dragDropOverlayEnabled = true
    @AppStorage("dragDropOverlayShowDevice") private var dragDropOverlayShowDevice = true
    @AppStorage("dragDropOverlayShowProgress") private var dragDropOverlayShowProgress = true
    @AppStorage("dragDropOverlayScale") private var dragDropOverlayScale = 1.0
    @AppStorage("dragDropOverlayPosition") private var dragDropOverlayPosition = "top"

    @State private var selectedDevice: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(MBLocalized("Global Defaults")) {
                Toggle(MBLocalized("Show Overlay"), isOn: self.$dragDropOverlayEnabled)

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(MBLocalized("Show Device Name"), isOn: self.$dragDropOverlayShowDevice)
                    Toggle(MBLocalized("Show Progress"), isOn: self.$dragDropOverlayShowProgress)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text(MBLocalized("Size"))
                            HStack {
                                Slider(
                                    value: self.$dragDropOverlayScale, in: 0.85 ... 1.3, step: 0.05)
                                    .frame(width: 120)
                                Text("\(Int(self.dragDropOverlayScale * 100))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }

                        GridRow {
                            Text(MBLocalized("Position"))
                            Picker("", selection: self.$dragDropOverlayPosition) {
                                Text(MBLocalized("Top")).tag("top")
                                Text(MBLocalized("Bottom")).tag("bottom")
                                Text(MBLocalized("Top Left")).tag("topLeading")
                                Text(MBLocalized("Top Right")).tag("topTrailing")
                                Text(MBLocalized("Bottom Left")).tag(
                                    "bottomLeading")
                                Text(MBLocalized("Bottom Right")).tag(
                                    "bottomTrailing")
                            }
                            .frame(width: 140)
                        }
                    }
                }
                .disabled(!self.dragDropOverlayEnabled)
                .padding(.leading, 20)
            }

            Divider()

            SettingsSection(MBLocalized("Per-Device Override")) {
                HStack {
                    Text(MBLocalized("Target Device"))
                    Picker("", selection: self.$selectedDevice) {
                        ForEach(self.deviceOptions, id: \.self) { device in
                            Text(device).tag(device)
                        }
                    }
                    .frame(width: 200)
                }

                if !self.selectedDevice.isEmpty {
                    Toggle(MBLocalized("Override Global Settings"), isOn: self.useOverrideBinding)
                        .padding(.top, 4)

                    if self.overlayPreferences.hasOverride(for: self.selectedDevice) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(MBLocalized("Show Device Name"), isOn: self.showDeviceBinding)
                            Toggle(MBLocalized("Show Progress"), isOn: self.showProgressBinding)

                            HStack {
                                Text(MBLocalized("Size"))
                                Slider(value: self.scaleBinding, in: 0.85 ... 1.3, step: 0.05)
                                    .frame(width: 120)
                                Text("\(Int(self.scaleBinding.wrappedValue * 100))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        }
        .onAppear {
            if self.selectedDevice.isEmpty {
                self.selectedDevice = self.networkManager.localDisplayName
            }
        }
    }

    // MARK: - Helpers

    private var deviceOptions: [String] {
        let connected = self.networkManager.connectedMachines.map(\.name)
        let stored = self.overlayPreferences.allDeviceNames()
        let base = [networkManager.localDisplayName] + connected
        return Array(Set(base + stored)).sorted()
    }

    private var defaultOverlayPreferences: MBOverlayPreferences {
        let position = MBOverlayPosition(rawValue: dragDropOverlayPosition) ?? .top
        return MBOverlayPreferences(
            showDevice: self.dragDropOverlayShowDevice,
            showProgress: self.dragDropOverlayShowProgress,
            scale: self.dragDropOverlayScale,
            position: position)
    }

    private var currentDevicePreferences: MBOverlayPreferences {
        self.overlayPreferences.preferences(
            for: self.selectedDevice, default: self.defaultOverlayPreferences)
    }

    private var useOverrideBinding: Binding<Bool> {
        Binding(
            get: { self.overlayPreferences.hasOverride(for: self.selectedDevice) },
            set: { enabled in
                if enabled {
                    self.overlayPreferences.setOverride(
                        self.currentDevicePreferences, for: self.selectedDevice)
                } else {
                    self.overlayPreferences.clearOverride(for: self.selectedDevice)
                }
            })
    }

    private var showDeviceBinding: Binding<Bool> {
        Binding(
            get: { self.currentDevicePreferences.showDevice },
            set: { val in self.updateDevicePreferences { $0.showDevice = val } })
    }

    private var showProgressBinding: Binding<Bool> {
        Binding(
            get: { self.currentDevicePreferences.showProgress },
            set: { val in self.updateDevicePreferences { $0.showProgress = val } })
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { self.currentDevicePreferences.scale },
            set: { val in self.updateDevicePreferences { $0.scale = val } })
    }

    private func updateDevicePreferences(_ update: (inout MBOverlayPreferences) -> Void) {
        var prefs = self.currentDevicePreferences
        update(&prefs)
        self.overlayPreferences.setOverride(prefs, for: self.selectedDevice)
    }
}

#Preview {
    SettingsView()
        .environment(MagicBorderKit.MBNetworkManager.shared)
        .environment(MBAccessibilityService())
        .environment(MBOverlayPreferencesStore())
}
