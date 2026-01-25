import AppKit
import MagicBorderKit
import SwiftUI

struct PairingFlowView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager:
        MagicBorderKit.MBNetworkManager

    @Binding var securityKey: String
    @State private var ipAddress: String = ""
    @State private var showGuide = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Windows Pairing", systemImage: "windowslogo")
                        .font(.headline)
                    Spacer()
                    Button("Guide") {
                        showGuide = true
                    }
                    .buttonStyle(.link)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Install Mouse Without Borders on Windows")
                    Text("2. Use the same Security Key on both devices")
                    Text("3. Allow ports 15100/15101 in Windows Firewall")
                    Text("4. Make sure both devices are on the same subnet")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Copy Key") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(securityKey, forType: .string)
                    }
                    .buttonStyle(.bordered)

                    Button("Refresh Key") {
                        securityKey = String(UUID().uuidString.prefix(16))
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .foregroundStyle(.secondary)
                        
                    TextField("Windows IP (e.g. 192.168.1.12)", text: $ipAddress)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onSubmit {
                            if !ipAddress.isEmpty {
                                networkManager.connectToHost(ip: ipAddress)
                            }
                        }

                    Button("Connect") {
                        networkManager.connectToHost(ip: ipAddress)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ipAddress.isEmpty)
                }

                Text("Tip: If pairing fails, disable VPN and verify the key matches on both devices.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showGuide) {
            WindowsPairingGuideView(securityKey: securityKey)
        }
    }
}

private struct WindowsPairingGuideView: View {
    let securityKey: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Windows Pairing Guide")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("• Install Mouse Without Borders (PowerToys version is supported)")
                Text("• Open Settings → Security Key and paste:")
                Text(securityKey)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                Text("• Allow ports 15100 (clipboard) and 15101 (control) in Windows Firewall")
                Text("• Ensure both machines are on the same LAN/subnet")
            }
            .font(.callout)

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520, height: 400)
    }
}