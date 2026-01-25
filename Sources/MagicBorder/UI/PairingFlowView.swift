import AppKit
import MagicBorderKit
import SwiftUI

struct PairingFlowView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager:
        MagicBorderKit.MBNetworkManager

    @Binding var securityKey: String
    @State private var ipAddress: String = ""
    @State private var showGuide = false
    @State private var isConnecting = false
    @State private var toastMessage: String = ""
    @State private var showToast = false

    private var trimmedKey: String {
        securityKey.replacingOccurrences(of: " ", with: "")
    }

    private var isKeyValid: Bool {
        trimmedKey.count >= 16
    }

    var body: some View {
        GroupBox {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Windows Pairing", systemImage: "windowslogo")
                            .font(.headline)
                        Spacer()
                        if isConnecting {
                            ConnectionStatusBadge(title: "连接中")
                        }
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

                    PairingCardView(securityKey: $securityKey)

                    HStack(spacing: 8) {
                        Image(systemName: isKeyValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isKeyValid ? .green : .orange)
                        Text(isKeyValid ? "Security Key 就绪" : "Security Key 至少 16 位")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Image(systemName: "network")
                            .foregroundStyle(.secondary)

                        TextField("Windows IP (e.g. 192.168.1.12)", text: $ipAddress)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .onSubmit {
                                if !ipAddress.isEmpty && isKeyValid {
                                    startConnecting()
                                }
                            }

                        Button("Connect") {
                            startConnecting()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(ipAddress.isEmpty || !isKeyValid)
                    }

                    Text("Tip: If pairing fails, disable VPN and verify the key matches on both devices.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if showToast {
                    ToastView(message: toastMessage)
                        .padding(8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showGuide) {
            WindowsPairingGuideView(securityKey: securityKey, isKeyValid: isKeyValid)
        }
        .onChange(of: networkManager.connectedMachines) { _, newValue in
            if newValue.isEmpty {
                showToast(text: "连接已断开")
            } else {
                showToast(text: "连接成功")
            }
        }
    }

    private func startConnecting() {
        guard !ipAddress.isEmpty, isKeyValid else { return }
        isConnecting = true
        networkManager.connectToHost(ip: ipAddress)
        showToast(text: "已发送连接请求")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isConnecting = false
        }
    }

    private func showToast(text: String) {
        toastMessage = text
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.2)) {
                showToast = false
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

            VStack(alignment: .leading, spacing: 12) {
                GuideStepRow(index: 1, title: "Install Mouse Without Borders (PowerToys version is supported)", isHighlighted: highlightedStep == 1)
                    .onTapGesture { highlightedStep = 1 }

                GuideStepRow(index: 2, title: "Open Settings → Security Key and paste:", isHighlighted: highlightedStep == 2)
                    .onTapGesture { highlightedStep = 2 }

                Text(securityKey)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    Image(systemName: isKeyValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isKeyValid ? .green : .orange)
                    Text(isKeyValid ? "Security Key 格式正确" : "Security Key 至少 16 位")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GuideStepRow(index: 3, title: "Allow ports 15100 (clipboard) and 15101 (control) in Windows Firewall", isHighlighted: highlightedStep == 3)
                    .onTapGesture { highlightedStep = 3 }

                GuideStepRow(index: 4, title: "Ensure both machines are on the same LAN/subnet", isHighlighted: highlightedStep == 4)
                    .onTapGesture { highlightedStep = 4 }
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

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(radius: 6, y: 2)
    }
}

private struct GuideStepRow: View {
    let index: Int
    let title: String
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.caption)
                .frame(width: 22, height: 22)
                .background(isHighlighted ? Color.blue.opacity(0.2) : Color.primary.opacity(0.05))
                .cornerRadius(6)
            Text(title)
                .foregroundStyle(isHighlighted ? .primary : .secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isHighlighted ? Color.blue.opacity(0.08) : Color.clear)
        .cornerRadius(8)
    }
}