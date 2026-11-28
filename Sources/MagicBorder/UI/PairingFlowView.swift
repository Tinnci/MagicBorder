import AppKit
import MagicBorderKit
import SwiftUI

struct PairingFlowView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager: MagicBorderKit.MBNetworkManager

    @Binding var securityKey: String
    @AppStorage("pairingIPAddress") private var ipAddress: String = ""
    @State private var showGuide = false
    @State private var showDoctor = false
    @State private var statusMessage: String?
    @State private var statusStyle: StatusStyle = .neutral
    @State private var showChecklist = false
    @State private var showDebugLog = false
    @State private var statusClearTask: Task<Void, Never>?

    private var trimmedKey: String {
        self.securityKey.replacingOccurrences(of: " ", with: "")
    }

    private var isKeyValid: Bool {
        self.networkManager.protocolMode == .modern || self.trimmedKey.count >= 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    self.networkManager.protocolMode == .mwbCompatibility
                        ? localizedString("Windows Pairing") : localizedString("Mac-to-Mac Pairing"),
                    systemImage: self.networkManager.protocolMode == .mwbCompatibility ? "pc" : "laptopcomputer"
                )
                .font(.headline)
                Spacer()
                if self.networkManager.isConnectingHost != nil {
                    ConnectionStatusBadge(title: localizedString("Connecting..."))
                }
                Button(action: { self.showGuide = true }) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(localizedString("Pairing Guide"))
            }

            if !self.networkManager.localIPv4Addresses().isEmpty {
                let myIP = self.networkManager.localIPv4Addresses().first ?? ""
                HStack {
                    Text(localizedString("This Mac IP"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(myIP)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button {
                        Self.copyToPasteboard(myIP)
                        self.showStatus(text: localizedString("Copied"), style: .success)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            if self.networkManager.protocolMode == .mwbCompatibility {
                DisclosureGroup(localizedString("Pairing checklist"), isExpanded: self.$showChecklist) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localizedString("1. Install Mouse Without Borders on Windows"))
                        Text(localizedString("2. Use the same Security Key on both devices"))
                        Text(localizedString("3. Allow ports 15100/15101 in Windows Firewall"))
                        Text(localizedString("4. Make sure both devices are on the same subnet"))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }

            PairingCardView(securityKey: self.$securityKey)

            Label(
                self.keyStatusTitle,
                systemImage: self.isKeyValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(self.isKeyValid ? .green : .orange)

            if let message = statusMessage {
                Label(message, systemImage: self.statusStyle.iconName)
                    .font(.caption)
                    .foregroundStyle(self.statusStyle.color)
            }

            if !self.networkManager.savedHosts.hosts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localizedString("Saved Hosts"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(self.networkManager.savedHosts.hosts.prefix(5)) { host in
                                Button {
                                    self.ipAddress = host.address
                                    self.networkManager.compatibilitySettings.protocolMode = host.protocolMode
                                    self.networkManager.applyCompatibilitySettings()
                                    self.networkManager.connectToHost(ip: host.address, port: host.messagePort)
                                } label: {
                                    Text(host.name)
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .contextMenu {
                                    Button(localizedString("Remove"), role: .destructive) {
                                        self.networkManager.savedHosts.remove(id: host.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Text(localizedString("Host Address"))
                Spacer()
                TextField(localizedString("192.168.1.5"), text: self.$ipAddress)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .frame(width: 170)
            }

            HStack {
                Button(localizedString("Connect")) {
                    self.startConnecting()
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !self.isKeyValid)

                Button(localizedString("Diagnose")) {
                    self.showDoctor = true
                }
                .buttonStyle(.bordered)
            }

            DisclosureGroup(localizedString("Debug log"), isExpanded: self.$showDebugLog) {
                if self.networkManager.pairingDebugLog.isEmpty {
                    Text(localizedString("No logs yet"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(
                                Array(self.networkManager.pairingDebugLog.suffix(12)).reversed(),
                                id: \.self
                            ) { line in
                                Text(line)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 110)

                    HStack {
                        Button(localizedString("Copy Redacted Log")) {
                            Self.copyToPasteboard(self.networkManager.redactedDiagnosticsText())
                            self.showStatus(text: localizedString("Copied"), style: .success)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(localizedString("Clear")) {
                            self.networkManager.clearPairingDiagnostics()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                    }
                }
            }
        }
        .sheet(isPresented: self.$showGuide) {
            WindowsPairingGuideView(securityKey: self.securityKey, isKeyValid: self.trimmedKey.count >= 16)
        }
        .sheet(isPresented: self.$showDoctor) {
            ConnectionDoctorView(initialHost: self.ipAddress)
        }
        .onChange(of: self.networkManager.connectedMachines) { oldValue, newValue in
            if !oldValue.isEmpty, newValue.isEmpty {
                self.showStatus(text: localizedString("Connection lost"), style: .warning)
            } else if !newValue.isEmpty {
                self.showStatus(text: localizedString("Connected successfully"), style: .success)
            }
        }
        .alert(
            localizedString("Pairing Error"),
            isPresented: Binding(
                get: { self.networkManager.pairingError != nil },
                set: { if !$0 { self.networkManager.pairingError = nil } })
        ) {
            Button(localizedString("Copy Details")) {
                Self.copyToPasteboard(self.networkManager.pairingError ?? "")
            }
            Button(localizedString("OK"), role: .cancel) {}
        } message: {
            Text(self.networkManager.pairingError ?? "")
        }
    }

    private var keyStatusTitle: String {
        if self.networkManager.protocolMode == .modern {
            return self.trimmedKey.isEmpty
                ? localizedString("Optional key empty (LAN only)")
                : localizedString("HMAC Key Configured")
        }
        return self.trimmedKey.count >= 16
            ? localizedString("Key Ready") : localizedString("At least 16 characters")
    }

    private func startConnecting() {
        let trimmedIP = self.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIP.isEmpty, self.isKeyValid else { return }
        self.ipAddress = trimmedIP
        self.networkManager.applyCompatibilitySettings()
        self.networkManager.clearPairingDiagnostics()
        self.networkManager.appendPairingLog("User initiated connect")
        self.networkManager.connectToHost(ip: trimmedIP)
        self.showStatus(text: localizedString("Connection request sent"), style: .neutral)
    }

    private func showStatus(text: String, style: StatusStyle) {
        self.statusMessage = text
        self.statusStyle = style
        self.statusClearTask?.cancel()
        self.statusClearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            if self.statusMessage == text {
                self.statusMessage = nil
            }
        }
    }

    private static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct WindowsPairingGuideView: View {
    let securityKey: String
    let isKeyValid: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedString("1. Install Software"))
                            .font(.headline)
                        Text(
                            localizedString(
                                "Install Mouse Without Borders (included in PowerToys) on your Windows machine.")
                        )
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedString("2. Verify Security Key"))
                            .font(.headline)
                        Text(localizedString("Open Settings -> Security Key and ensure it matches:"))
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(self.securityKey)
                                .font(.system(.body, design: .monospaced))
                                .padding(6)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                                .textSelection(.enabled)

                            if self.isKeyValid {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                        .padding(.top, 4)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedString("3. Check Firewall"))
                            .font(.headline)
                        Text(localizedString("Ensure ports 15100 and 15101 are allowed in Windows Firewall."))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedString("4. Network Check"))
                            .font(.headline)
                        Text(localizedString("Both devices must be on the same local network subnet."))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(localizedString("Windows Pairing Guide"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizedString("Done")) {
                        self.dismiss()
                    }
                }
            }
        }
        .frame(width: 480, height: 420)
    }
}

private struct ConnectionStatusBadge: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.6)
            Text(self.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Material.thin)
        .clipShape(.rect(cornerRadius: 8))
    }
}

private enum StatusStyle {
    case neutral
    case success
    case warning

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .success: .green
        case .warning: .orange
        }
    }

    var iconName: String {
        switch self {
        case .neutral: "info.circle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }
}
