import MagicBorderKit
import Observation
import SwiftUI

// MARK: - Subviews

private struct StatusDot: View {
    var active: Bool
    var body: some View {
        Circle()
            .fill(active ? Color.green : Color.red)
            .frame(width: 8, height: 8)
    }
}

private struct DashboardHeader: View {
    @Environment(MBAccessibilityService.self) private var accessibilityService:
        MBAccessibilityService
    @Binding var showSettings: Bool

    var body: some View {
        HStack {
            Text("MagicBorder")
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            HStack(spacing: 8) {
                StatusDot(active: accessibilityService.isTrusted)
                Text(
                    accessibilityService.isTrusted ? "Ready" : "Accessibility Permission Needed"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button(action: {
                    showSettings.toggle()
                }) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings) {
                    SettingsView()
                }
            }
        }
    }
}

private struct DashboardFooter: View {
    @Environment(MagicBorderKit.MBInputManager.self) private var inputManager:
        MagicBorderKit.MBInputManager

    var body: some View {
        HStack {
            Spacer()
            Button(action: {
                inputManager.toggleInterception(!inputManager.isIntercepting)
            }) {
                HStack {
                    Image(
                        systemName: inputManager.isIntercepting
                            ? "stop.circle.fill" : "play.circle.fill")
                    Text(
                        inputManager.isIntercepting ? "Stop Interception" : "Start Interception"
                    )
                }
                .font(.title3)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(inputManager.isIntercepting ? .red : .green)
            Spacer()
        }
    }
}

struct DiscoveredDevicesView: View {
    var networkManager: MBNetworkManager

    var body: some View {
        if !networkManager.discoveredPeers.isEmpty {
            VStack(alignment: .leading) {
                Text("Discovered")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(networkManager.discoveredPeers) { peer in
                            Button(action: {
                                networkManager.connect(to: peer.endpoint)
                            }) {
                                VStack {
                                    Image(
                                        systemName: peer.type == .scanned ? "pc" : "laptopcomputer")
                                    Text(peer.name)
                                        .font(.caption)
                                }
                                .padding()
                                .background(Material.ultraThin)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: - Main View

struct DashboardView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager:
        MagicBorderKit.MBNetworkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService:
        MBAccessibilityService
    @Environment(MagicBorderKit.MBInputManager.self) private var inputManager:
        MagicBorderKit.MBInputManager

    @Binding var showSettings: Bool

    @State private var machines: [Machine] = [
        Machine(id: UUID(), name: Host.current().localizedName ?? "Local Mac", isOnline: true)
    ]

    @SceneStorage("securityKey") private var securityKey: String = "YOUR_SECURE_KEY_123"

    var body: some View {
        VStack(spacing: 24) {
            DashboardHeader(showSettings: $showSettings)
                .padding([.horizontal, .top])

            // Warnings
            if !accessibilityService.isTrusted {
                Button("Grant Permission") {
                    accessibilityService.promptForPermission()
                }
                .buttonStyle(.borderedProminent)
            }

            // Arrangement Matrix
            VStack(alignment: .leading) {
                Text("Arrangement")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.leading)

                MachineMatrixView(machines: $machines)
                    .frame(height: 120)
            }

            DiscoveredDevicesView(networkManager: networkManager)

            PairingCardView(securityKey: $securityKey)
                .padding(.horizontal)

            Spacer()

            DashboardFooter()
                .padding(.bottom)
        }
        .frame(minWidth: 600, minHeight: 450)
        .background(Material.regular)
        .onChange(of: networkManager.connectedMachines, initial: true) { _, connected in
            updateMachines(from: connected)
        }
    }

    private func updateMachines(from connected: [MBNetworkManager.ConnectedMachine]) {
        var newMachines = [
            Machine(id: UUID(), name: Host.current().localizedName ?? "Local Mac", isOnline: true)
        ]

        for peer in connected {
            newMachines.append(Machine(id: peer.id, name: peer.name, isOnline: true))
        }

        self.machines = newMachines
    }
}
