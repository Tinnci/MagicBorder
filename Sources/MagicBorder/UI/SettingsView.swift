import AppKit
import MagicBorderKit
import SwiftUI

struct SettingsView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    private let settingsWindowWidth: CGFloat = 540

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label(localizedString("General"), systemImage: "gear")
                }
                .frame(width: self.settingsWindowWidth)

            InputSettingsTab()
                .tabItem {
                    Label(localizedString("Input"), systemImage: "keyboard")
                }
                .frame(width: self.settingsWindowWidth)

            NetworkSettingsTab()
                .tabItem {
                    Label(localizedString("Network"), systemImage: "antenna.radiowaves.left.and.right")
                }
                .frame(width: self.settingsWindowWidth)

            OverlaySettingsTab()
                .tabItem {
                    Label(localizedString("Overlay"), systemImage: "macwindow.on.rectangle")
                }
                .frame(width: self.settingsWindowWidth)
        }
        .padding(20)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

private struct GeneralSettingsTab: View {
    @Environment(MBAppController.self) private var controller
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @State private var showOnboarding = false

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { self.controller.launchAtLogin },
            set: { self.controller.setLaunchAtLogin($0) })
    }

    var body: some View {
        @Bindable var controller = controller
        @Bindable var networkManager = networkManager

        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(localizedString("Startup & Menu Bar")) {
                Toggle(localizedString("Launch at Login"), isOn: self.launchBinding)
                if let error = self.controller.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle(localizedString("Menu Bar Only (Hide Dock Icon)"), isOn: $controller.hideDockIcon)
            }

            Divider()

            SettingsSection(localizedString("Clipboard & Privacy")) {
                Toggle(
                    localizedString("Share Clipboard"),
                    isOn: $networkManager.compatibilitySettings.shareClipboard)
                Toggle(
                    localizedString("Transfer Files"),
                    isOn: $networkManager.compatibilitySettings.transferFiles)
                Toggle(
                    localizedString("Ignore Password Manager Items"),
                    isOn: $networkManager.compatibilitySettings.ignoreConcealedClipboard)

                HStack {
                    Text(localizedString("Max Clipboard Size"))
                    Picker("", selection: $networkManager.compatibilitySettings.maxClipboardSizeMB) {
                        Text("2 MB").tag(2)
                        Text("5 MB").tag(5)
                        Text("10 MB").tag(10)
                        Text("25 MB").tag(25)
                    }
                    .frame(width: 110)
                }
            }

            Divider()

            SettingsSection(localizedString("Setup Guide")) {
                Button(localizedString("Open Setup Assistant...")) {
                    self.showOnboarding = true
                }
            }
        }
        .sheet(isPresented: self.$showOnboarding) {
            OnboardingView()
        }
    }
}

private struct NetworkSettingsTab: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @State private var doctorHost = ""
    @State private var showDoctor = false

    var body: some View {
        @Bindable var networkManager = networkManager

        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(localizedString("Protocol Mode")) {
                Picker(
                    localizedString("Mode"),
                    selection: $networkManager.compatibilitySettings.protocolMode
                ) {
                    Text(localizedString("Windows (MWB Compatibility)")).tag(MBProtocolMode.mwbCompatibility)
                    Text(localizedString("Mac-to-Mac (Modern)")).tag(MBProtocolMode.modern)
                }
                .pickerStyle(.segmented)

                if let ip = self.networkManager.localIPv4Addresses().first {
                    HStack {
                        Text(localizedString("This Mac LAN IP: %@", arguments: [ip]))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Button(localizedString("Copy")) {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(ip, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }

            Divider()

            SettingsSection(localizedString("Security")) {
                PairingCardView(securityKey: $networkManager.compatibilitySettings.securityKey)

                HStack {
                    Button(localizedString("Validate")) {
                        _ = networkManager.compatibilitySettings.validateSecurityKey()
                    }
                    if let status = networkManager.compatibilitySettings.validationStatus {
                        Text(status.localizedMessage)
                            .font(.caption)
                            .foregroundStyle(status == .valid ? .green : .red)
                    }
                }
            }

            Divider()

            SettingsSection(localizedString("Ports & Diagnostics")) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text(localizedString("Message Port"))
                        TextField(
                            localizedString("15101"),
                            value: $networkManager.compatibilitySettings.messagePort,
                            format: .number.grouping(.never)
                        )
                        .monospacedDigit()
                        .frame(width: 90)
                        Text(localizedString("Default: 15101"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text(localizedString("Clipboard Port"))
                        TextField(
                            localizedString("15100"),
                            value: $networkManager.compatibilitySettings.clipboardPort,
                            format: .number.grouping(.never)
                        )
                        .monospacedDigit()
                        .frame(width: 90)
                        Text(localizedString("Default: 15100"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(localizedString("Run Connection Doctor...")) {
                    self.doctorHost = self.networkManager.savedHosts.hosts.first?.address ?? ""
                    self.showDoctor = true
                }
            }
        }
        .sheet(isPresented: self.$showDoctor) {
            ConnectionDoctorView(initialHost: self.doctorHost)
        }
    }
}

private struct OverlaySettingsTab: View {
    @Environment(MBAppController.self) private var controller
    @Environment(MBOverlayPreferencesStore.self) private var overlayPreferences
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager

    @AppStorage("dragDropOverlayEnabled") private var dragDropOverlayEnabled = true
    @AppStorage("dragDropOverlayShowDevice") private var dragDropOverlayShowDevice = true
    @AppStorage("dragDropOverlayShowProgress") private var dragDropOverlayShowProgress = true
    @AppStorage("dragDropOverlayScale") private var dragDropOverlayScale = 1.0
    @AppStorage("dragDropOverlayPosition") private var dragDropOverlayPosition = "top"

    @State private var selectedDevice: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(localizedString("Global Defaults")) {
                HStack {
                    Toggle(localizedString("Show Overlay"), isOn: self.$dragDropOverlayEnabled)
                    Spacer()
                    Button(localizedString("Preview Overlay")) {
                        self.controller.previewDragDropOverlay()
                    }
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(localizedString("Show Device Name"), isOn: self.$dragDropOverlayShowDevice)
                    Toggle(localizedString("Show Progress"), isOn: self.$dragDropOverlayShowProgress)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text(localizedString("Size"))
                            HStack {
                                Slider(value: self.$dragDropOverlayScale, in: 0.85...1.3, step: 0.05)
                                    .frame(width: 120)
                                Text("\(Int(self.dragDropOverlayScale * 100))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }

                        GridRow {
                            Text(localizedString("Position"))
                            self.positionPicker(selection: self.$dragDropOverlayPosition)
                        }
                    }
                }
                .disabled(!self.dragDropOverlayEnabled)
                .padding(.leading, 20)
            }

            Divider()

            SettingsSection(localizedString("Per-Device Override")) {
                HStack {
                    Text(localizedString("Target Device"))
                    Picker("", selection: self.$selectedDevice) {
                        ForEach(self.deviceOptions, id: \.self) { device in
                            Text(device).tag(device)
                        }
                    }
                    .frame(width: 220)
                }

                if !self.selectedDevice.isEmpty {
                    Toggle(localizedString("Override Global Settings"), isOn: self.useOverrideBinding)
                        .padding(.top, 4)

                    if self.overlayPreferences.hasOverride(for: self.selectedDevice) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(localizedString("Show Device Name"), isOn: self.showDeviceBinding)
                            Toggle(localizedString("Show Progress"), isOn: self.showProgressBinding)

                            HStack {
                                Text(localizedString("Size"))
                                Slider(value: self.scaleBinding, in: 0.85...1.3, step: 0.05)
                                    .frame(width: 120)
                                Text("\(Int(self.scaleBinding.wrappedValue * 100))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text(localizedString("Position"))
                                self.positionPicker(selection: self.positionBinding)
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

    @ViewBuilder
    private func positionPicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            Text(localizedString("Top")).tag("top")
            Text(localizedString("Bottom")).tag("bottom")
            Text(localizedString("Top Left")).tag("topLeading")
            Text(localizedString("Top Right")).tag("topTrailing")
            Text(localizedString("Bottom Left")).tag("bottomLeading")
            Text(localizedString("Bottom Right")).tag("bottomTrailing")
        }
        .frame(width: 150)
    }

    private var deviceOptions: [String] {
        let connected = self.networkManager.connectedMachines.map(\.name)
        let stored = self.overlayPreferences.allDeviceNames()
        let base = [self.networkManager.localDisplayName] + connected
        return Array(Set(base + stored)).sorted()
    }

    private var defaultOverlayPreferences: MBOverlayPreferences {
        let position = MBOverlayPosition(rawValue: self.dragDropOverlayPosition) ?? .top
        return MBOverlayPreferences(
            showDevice: self.dragDropOverlayShowDevice,
            showProgress: self.dragDropOverlayShowProgress,
            scale: self.dragDropOverlayScale,
            position: position)
    }

    private var currentDevicePreferences: MBOverlayPreferences {
        self.overlayPreferences.preferences(for: self.selectedDevice, default: self.defaultOverlayPreferences)
    }

    private var useOverrideBinding: Binding<Bool> {
        Binding(
            get: { self.overlayPreferences.hasOverride(for: self.selectedDevice) },
            set: { enabled in
                if enabled {
                    self.overlayPreferences.setOverride(self.currentDevicePreferences, for: self.selectedDevice)
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

    private var positionBinding: Binding<String> {
        Binding(
            get: { self.currentDevicePreferences.position.rawValue },
            set: { raw in
                let position = MBOverlayPosition(rawValue: raw) ?? .top
                self.updateDevicePreferences { $0.position = position }
            })
    }

    private func updateDevicePreferences(_ update: (inout MBOverlayPreferences) -> Void) {
        var prefs = self.currentDevicePreferences
        update(&prefs)
        self.overlayPreferences.setOverride(prefs, for: self.selectedDevice)
    }
}
