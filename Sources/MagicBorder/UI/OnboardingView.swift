import AppKit
import MagicBorderKit
import SwiftUI

struct OnboardingView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService
    @Environment(\.dismiss) private var dismiss

    @AppStorage("pairingIPAddress") private var ipAddress: String = ""
    @State private var step = 0
    @State private var showDoctor = false

    private var trimmedKey: String {
        self.networkManager.compatibilitySettings.securityKey.replacingOccurrences(of: " ", with: "")
    }

    private var isKeyReady: Bool {
        self.networkManager.protocolMode == .modern || self.trimmedKey.count >= 16
    }

    var body: some View {
        @Bindable var networkManager = networkManager

        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedString("Welcome to MagicBorder"))
                        .font(.title2.bold())
                    Text(localizedString("Step %d of 3", arguments: [self.step + 1]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(localizedString("Skip")) {
                    self.finishOnboarding()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(self.step + 1), total: 3)

            Group {
                switch self.step {
                case 0:
                    self.permissionsStep
                case 1:
                    self.pairingStep(networkManager: networkManager)
                default:
                    self.readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                if self.step > 0 {
                    Button(localizedString("Back")) {
                        self.step -= 1
                    }
                }
                Spacer()
                if self.step < 2 {
                    Button(localizedString("Next")) {
                        self.step += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(localizedString("Finish Setup")) {
                        self.finishOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 540, height: 470)
        .sheet(isPresented: self.$showDoctor) {
            ConnectionDoctorView(initialHost: self.ipAddress)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizedString("1. Grant Input Permission"))
                .font(.headline)
            Text(
                localizedString(
                    "macOS requires Accessibility access so MagicBorder can capture edge crossings and forward mouse & keyboard events."
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            GroupBox {
                HStack(spacing: 12) {
                    Image(
                        systemName: self.accessibilityService.isTrusted
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.title2)
                    .foregroundStyle(self.accessibilityService.isTrusted ? .green : .orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            self.accessibilityService.isTrusted
                                ? localizedString("Accessibility Granted")
                                : localizedString("Accessibility Required")
                        )
                        .font(.headline)
                        Text(localizedString("Updates automatically as soon as enabled in System Settings."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !self.accessibilityService.isTrusted {
                        Button(localizedString("Open System Settings")) {
                            self.accessibilityService.openSystemSettings()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(6)
            }
        }
    }

    @ViewBuilder
    private func pairingStep(networkManager: MBNetworkManager) -> some View {
        @Bindable var networkManager = networkManager

        VStack(alignment: .leading, spacing: 12) {
            Text(localizedString("2. Pair Your First Machine"))
                .font(.headline)

            Picker(localizedString("Protocol Mode"), selection: $networkManager.compatibilitySettings.protocolMode) {
                Text(localizedString("Windows (MWB)")).tag(MBProtocolMode.mwbCompatibility)
                Text(localizedString("Mac-to-Mac (Modern)")).tag(MBProtocolMode.modern)
            }
            .pickerStyle(.segmented)

            if let ip = self.networkManager.localIPv4Addresses().first {
                HStack {
                    Text(localizedString("This Mac LAN IP: %@", arguments: [ip]))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(localizedString("Copy")) {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(ip, forType: .string)
                    }
                    .controlSize(.mini)
                }
            }

            PairingCardView(securityKey: $networkManager.compatibilitySettings.securityKey)

            HStack {
                TextField(localizedString("Target Host IP (e.g. 192.168.1.5)"), text: self.$ipAddress)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Button(localizedString("Connect")) {
                    self.networkManager.applyCompatibilitySettings()
                    self.networkManager.connectToHost(ip: self.ipAddress)
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !self.isKeyReady)

                Button(localizedString("Diagnose")) {
                    self.showDoctor = true
                }
            }

            if !self.networkManager.connectedMachines.isEmpty {
                Label(
                    localizedString(
                        "Connected to %@",
                        arguments: [self.networkManager.connectedMachines.map(\.name).joined(separator: ", ")]),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
            }
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizedString("3. Tips & Shortcuts"))
                .font(.headline)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        localizedString("Move your cursor cleanly past a screen edge to switch machines."),
                        systemImage: "arrow.left.arrow.right")
                    Label(
                        localizedString("Double-tap Esc anytime while remote to return control to your Mac."),
                        systemImage: "escape")
                    Label(
                        localizedString("Use ⌃⌥L to lock to the current screen or ⌃⌥1–4 to jump directly."),
                        systemImage: "keyboard")
                    Label(
                        localizedString("Passwords copied from password managers stay local automatically."),
                        systemImage: "lock.shield")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
        }
    }

    private func finishOnboarding() {
        self.networkManager.compatibilitySettings.onboardingCompleted = true
        self.dismiss()
    }
}
