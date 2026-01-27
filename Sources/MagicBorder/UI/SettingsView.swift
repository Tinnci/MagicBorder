import MagicBorderKit
import SwiftUI

struct SettingsView: View {
    private let width: CGFloat = 500

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .frame(width: self.width)
            // Remove explicit padding here as TabView content usually needs its own padding
            // But generally, we want some padding inside the tab content.

            NetworkSettingsTab()
                .tabItem {
                    Label("Network", systemImage: "antenna.radiowaves.left.and.right")
                }
                .frame(width: self.width)

            OverlaySettingsTab()
                .tabItem {
                    Label("Overlay", systemImage: "macwindow.on.rectangle")
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
            SettingsSection("Clipboard & Files") {
                Toggle(
                    "Share Clipboard", isOn: $networkManager.compatibilitySettings.shareClipboard)
                Toggle("Transfer Files", isOn: $networkManager.compatibilitySettings.transferFiles)
            }

            Divider()

            SettingsSection("Cursor Control") {
                Toggle("Capture Local Input", isOn: self.$captureInput)
                    .disabled(!self.accessibilityService.isTrusted)

                if !self.accessibilityService.isTrusted {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Permission Required")
                                .font(.headline)
                            Text(
                                "MagicBorder needs accessibility access to share mouse and keyboard input.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Open System Settings") {
                                self.accessibilityService.openSystemSettings()
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                }

                Toggle(
                    "Switch by Moving to Edge",
                    isOn: $networkManager.compatibilitySettings.switchByMouse)
                Toggle(
                    "Block Corner Switching",
                    isOn: $networkManager.compatibilitySettings.blockCorners)
                Toggle(
                    "Center Cursor on Manual Switch",
                    isOn: $networkManager.compatibilitySettings.centerCursorOnManualSwitch)

                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("Edge Switch Lock")
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
                        Text("Edge Safe Margin", comment: "Label for edge margin slider settings")
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

                Toggle("Wrap Mouse at Screen Edge", isOn: self.$wrapMouse)
                Toggle("Hide Mouse at Edge", isOn: self.$hideMouse)
                Toggle(
                    "Relative Mouse Movement",
                    isOn: $networkManager.compatibilitySettings.moveMouseRelatively)
            }

            Divider()

            SettingsSection("Matrix Configuration") {
                Picker("Layout Mode", selection: self.matrixModeBinding) {
                    Text("Single Row", comment: "Layout mode where machines are in one line").tag(0)
                    Text("Grid (2 Rows)", comment: "Layout mode with two rows").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden() // Segmented picker shows labels inside
                .frame(width: 250)

                Toggle(
                    "Cycle Through Screens",
                    isOn: $networkManager.compatibilitySettings.matrixCircle)

                Text(
                    networkManager.compatibilitySettings.matrixOneRow
                        ? "Machines are arranged in a single horizontal line."
                        : "Machines are arranged in a 2-row grid layout.")
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
            SettingsSection("Security") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        SecureField(
                            "Security Key", text: $networkManager.compatibilitySettings.securityKey)
                            .textContentType(.password)
                            .frame(width: 240)

                        if let message = networkManager.compatibilitySettings.validationMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(message.contains("Success") ? .green : .red)
                        }
                    }

                    Button("Validate") {
                        _ = networkManager.compatibilitySettings.validateSecurityKey()
                    }
                }
            }

            Divider()

            SettingsSection("Ports") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("Message Port")
                        TextField(
                            "20000", value: $networkManager.compatibilitySettings.messagePort,
                            formatter: NumberFormatter())
                            .monospacedDigit()
                            .frame(width: 80)
                        Text("Default: 20000").font(.caption).foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("Clipboard Port")
                        TextField(
                            "20001", value: $networkManager.compatibilitySettings.clipboardPort,
                            formatter: NumberFormatter())
                            .monospacedDigit()
                            .frame(width: 80)
                        Text("Default: 20001").font(.caption).foregroundStyle(.secondary)
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
            SettingsSection("Global Defaults") {
                Toggle("Show Overlay", isOn: self.$dragDropOverlayEnabled)

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show Device Name", isOn: self.$dragDropOverlayShowDevice)
                    Toggle("Show Progress", isOn: self.$dragDropOverlayShowProgress)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("Size")
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
                            Text("Position")
                            Picker("", selection: self.$dragDropOverlayPosition) {
                                Text("Top", comment: "Overlay position").tag("top")
                                Text("Bottom", comment: "Overlay position").tag("bottom")
                                Text("Top Left", comment: "Overlay position").tag("topLeading")
                                Text("Top Right", comment: "Overlay position").tag("topTrailing")
                                Text("Bottom Left", comment: "Overlay position").tag(
                                    "bottomLeading")
                                Text("Bottom Right", comment: "Overlay position").tag(
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

            SettingsSection("Per-Device Override") {
                HStack {
                    Text("Target Device")
                    Picker("", selection: self.$selectedDevice) {
                        ForEach(self.deviceOptions, id: \.self) { device in
                            Text(device).tag(device)
                        }
                    }
                    .frame(width: 200)
                }

                if !self.selectedDevice.isEmpty {
                    Toggle("Override Global Settings", isOn: self.useOverrideBinding)
                        .padding(.top, 4)

                    if self.overlayPreferences.hasOverride(for: self.selectedDevice) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Show Device Name", isOn: self.showDeviceBinding)
                            Toggle("Show Progress", isOn: self.showProgressBinding)

                            HStack {
                                Text("Size")
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
