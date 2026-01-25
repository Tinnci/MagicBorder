import MagicBorderKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var networkManager: NetworkManager
    @EnvironmentObject var accessibilityService: AccessibilityService
    @EnvironmentObject var inputManager: InputManager

    @Binding var showSettings: Bool

    // Demo state for Matrix until NetworkManager fully supports MWB Peer List
    @State private var machines: [Machine] = [
        Machine(id: UUID(), name: Host.current().localizedName ?? "Local Mac", isOnline: true)
    ]

    @SceneStorage("securityKey") var securityKey: String = "YOUR_SECURE_KEY_123"

    var body: some View {
        VStack(spacing: 24) {
            // Header
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
            .padding(.horizontal)
            .padding(.top)

            // Warnings
            if !accessibilityService.isTrusted {
                Button("Grant Permission") {
                    accessibilityService.promptForPermission()
                }
                .buttonStyle(.borderedProminent)
            }

            // Machine Matrix
            VStack(alignment: .leading) {
                Text("Arrangement")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.leading)

                MachineMatrixView(machines: $machines)
                    .frame(height: 120)
            }

            // Discovered Devices
            DiscoveredDevicesView(networkManager: networkManager)

            // Pairing
            PairingCardView(securityKey: $securityKey)
                .padding(.horizontal)

            Spacer()

            // Footer Control
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
            .padding(.bottom)
        }
        .frame(minWidth: 600, minHeight: 450)
        .background(Material.regular)
        .onReceive(networkManager.$connectedMachines) { connected in
            updateMachines(from: connected)
        }
    }

    private func updateMachines(from connected: [NetworkManager.ConnectedMachine]) {
        // Keep local machine
        var newMachines = [
            Machine(id: UUID(), name: Host.current().localizedName ?? "Local Mac", isOnline: true)
        ]

        // Add connected
        for peer in connected {
            newMachines.append(Machine(id: peer.id, name: peer.name, isOnline: true))
        }

        self.machines = newMachines
    }
}

struct DiscoveredDevicesView: View {
    @ObservedObject var networkManager: NetworkManager

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
                                networkManager.connect(to: peer.endpoint)  // Need helper for Endpoint if connect(to: Result) expects result.
                                // Actually connect(to: Result) exists. I need connect(to: Endpoint).
                            }) {
                                VStack {
                                    Image(
                                        systemName: peer.type == .scanned ? "pc" : "laptopcomputer")  // SF Symbol varies?
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

// Reusing StatusDot from original App.swift logic if it exists, or redefining.
struct StatusDot: View {
    var active: Bool
    var body: some View {
        Circle()
            .fill(active ? Color.green : Color.red)
            .frame(width: 8, height: 8)
    }
}
