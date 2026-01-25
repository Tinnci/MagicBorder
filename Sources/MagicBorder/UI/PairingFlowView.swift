import AppKit
import MagicBorderKit
import SwiftUI

struct PairingFlowView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager:
        MagicBorderKit.MBNetworkManager

    @Binding var securityKey: String
    @AppStorage("pairingIPAddress") private var ipAddress: String = ""
    @State private var showGuide = false
    @State private var isConnecting = false
    @State private var statusMessage: String?
    @State private var statusStyle: StatusStyle = .neutral
    @State private var showChecklist = false
    @State private var showDebugLog = false

    private var trimmedKey: String {
        securityKey.replacingOccurrences(of: " ", with: "")
    }

    private var isKeyValid: Bool {
        trimmedKey.count >= 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Windows Pairing", systemImage: "windowslogo")
                    .font(.headline)
                Spacer()
                if isConnecting {
                    ConnectionStatusBadge(title: "连接中")
                }
                Button(action: { showGuide = true }) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Pairing Guide")
            }

            DisclosureGroup("Pairing checklist", isExpanded: $showChecklist) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Install Mouse Without Borders on Windows")
                    Text("2. Use the same Security Key on both devices")
                    Text("3. Allow ports 15100/15101 in Windows Firewall")
                    Text("4. Make sure both devices are on the same subnet")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }

            PairingCardView(securityKey: $securityKey)

            Label(
                isKeyValid ? "Key Ready" : "At least 16 characters",
                systemImage: isKeyValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(isKeyValid ? .green : .orange)

            if let message = statusMessage {
                Label(message, systemImage: statusStyle.iconName)
                    .font(.caption)
                    .foregroundStyle(statusStyle.color)
            }

            DisclosureGroup("Debug log", isExpanded: $showDebugLog) {
                if networkManager.pairingDebugLog.isEmpty {
                    Text("No logs yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(networkManager.pairingDebugLog.suffix(12)).reversed(), id: \.self) { line in
                                Text(line)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)

                    HStack {
                        Button("Copy Log") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(networkManager.pairingDebugLog.joined(separator: "\n"), forType: .string)
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }
            }

            HStack {
                Text("Windows IP")
                Spacer()
                TextField("192.168.1.5", text: $ipAddress)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .frame(width: 200)
            }

            Button("Connect") {
                startConnecting()
            }
            .disabled(ipAddress.isEmpty || !isKeyValid)
        }
        .sheet(isPresented: $showGuide) {
            WindowsPairingGuideView(securityKey: securityKey, isKeyValid: isKeyValid)
        }
        .onChange(of: networkManager.connectedMachines) { _, newValue in
            if newValue.isEmpty {
                showStatus(text: "连接已断开", style: .warning)
            } else {
                showStatus(text: "连接成功", style: .success)
            }
        }
        .alert(
            "Pairing Error",
            isPresented: Binding(
                get: { networkManager.pairingError != nil },
                set: { if !$0 { networkManager.pairingError = nil } }))
        {
            Button("Copy Details") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(networkManager.pairingError ?? "", forType: .string)
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(networkManager.pairingError ?? "")
        }
    }

    private func startConnecting() {
        guard !ipAddress.isEmpty, isKeyValid else { return }
        networkManager.clearPairingDiagnostics()
        networkManager.appendPairingLog("User initiated connect")
        isConnecting = true
        networkManager.connectToHost(ip: ipAddress)
        showStatus(text: "已发送连接请求", style: .neutral)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isConnecting = false
        }
    }

    private func showStatus(text: String, style: StatusStyle) {
        statusMessage = text
        statusStyle = style
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if statusMessage == text {
                statusMessage = nil
            }
        }
    }
}

private struct WindowsPairingGuideView: View {
    let securityKey: String
    let isKeyValid: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var highlightedStep: Int = 2

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Install Software")
                            .font(.headline)
                        Text(
                            "Install Mouse Without Borders (included in PowerToys) on your Windows machine.")
                            .foregroundStyle(.secondary)
                            .font(.body)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("2. Verify Security Key")
                            .font(.headline)
                        Text("Open Settings → Security Key and ensure it matches:")
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(securityKey)
                                .font(.system(.body, design: .monospaced))
                                .padding(6)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(4)
                                .textSelection(.enabled)

                            if isKeyValid {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                        .padding(.top, 4)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("3. Check Firewall")
                            .font(.headline)
                        Text(
                            "Ensure ports **15100** and **15101** are allowed in Windows Firewall.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("4. Network Check")
                            .font(.headline)
                        Text("Both devices must be on the same local network subnet.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Windows Pairing Guide")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 480, height: 450)
    }
}

private struct ConnectionStatusBadge: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Material.thin)
        .cornerRadius(8)
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
