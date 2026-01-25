/*
 * MagicBorder - A native macOS application for mouse and keyboard sharing.
 * Copyright (C) 2026 MagicBorder Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import MagicBorderKit
import SwiftUI

// MARK: - Main View

struct DashboardView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager:
        MagicBorderKit.MBNetworkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService:
        MBAccessibilityService
    @State private var selection: SidebarItem? = .arrangement
    @State private var searchText = ""
    @State private var isRefreshing = false

    // Stable ID for local machine to avoid list flashes
    private let localMachineId = UUID()

    @State private var machines: [Machine] = []

    @SceneStorage("securityKey") private var securityKey: String = "YOUR_SECURE_KEY_123"

    var filteredMachines: [Machine] {
        if searchText.isEmpty {
            return machines
        } else {
            return machines.filter { $0.name.localizedStandardContains(searchText) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Main") {
                    ForEach(SidebarItem.allCases) { item in
                        NavigationLink(value: item) {
                            Label(item.title, systemImage: item.icon)
                        }
                    }
                }

                Section("Machines") {
                    ForEach(filteredMachines) { machine in
                        NavigationLink(destination: MachineDetailView(machine: machine)) {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                Text(machine.name)
                                Spacer()
                                StatusDot(active: machine.isOnline)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("MagicBorder")
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search machines")
            .toolbar {
                ToolbarItem {
                    Button(action: { /* Add machine action */  }) {
                        Image(systemName: "plus")
                    }
                    .help("Add Machine")
                }
                ToolbarItem {
                    Button(action: refreshMachines) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(
                                isRefreshing
                                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default, value: isRefreshing)
                    }
                    .help("Refresh Machines")
                }
            }
        } detail: {
            if let selection = selection {
                switch selection {
                case .arrangement:
                    ArrangementDetailView(machines: $machines, securityKey: $securityKey)
                case .settings:
                    SettingsView()
                case .machines:
                    DiscoveredMachinesListView(networkManager: networkManager)
                }
            } else {
                Text("Select an item from the sidebar")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            networkManager.securityKey = securityKey
            networkManager.compatibilitySettings.securityKey = securityKey
            networkManager.applyCompatibilitySettings()

            // Ensure local machine has stable ID on start
            machines = [
                Machine(
                    id: localMachineId, name: Host.current().localizedName ?? "Local Mac",
                    isOnline: true)
            ]
        }
        .onChange(of: securityKey) { _, newValue in
            networkManager.securityKey = newValue
            networkManager.compatibilitySettings.securityKey = newValue
            networkManager.applyCompatibilitySettings()
        }
        .onChange(of: networkManager.connectedMachines, initial: true) { _, connected in
            updateMachines(from: connected)
        }
    }

    private func refreshMachines() {
        isRefreshing = true
        // Simulate a refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isRefreshing = false
        }
    }

    private func updateMachines(from connected: [MBNetworkManager.ConnectedMachine]) {
        var newMachines = [
            Machine(
                id: localMachineId, name: Host.current().localizedName ?? "Local Mac",
                isOnline: true)
        ]

        for peer in connected {
            newMachines.append(Machine(id: peer.id, name: peer.name, isOnline: true))
        }

        self.machines = newMachines
    }
}

// MARK: - Detail Views

struct ArrangementDetailView: View {
    @Binding var machines: [Machine]
    @Binding var securityKey: String
    @Environment(MBAccessibilityService.self) private var accessibilityService:
        MBAccessibilityService
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager:
        MagicBorderKit.MBNetworkManager

    private var matrixTwoRowBinding: Binding<Bool> {
        Binding(
            get: { !networkManager.compatibilitySettings.matrixOneRow },
            set: { networkManager.compatibilitySettings.matrixOneRow = !$0 }
        )
    }
    private var matrixSwapBinding: Binding<Bool> {
        Binding(
            get: { networkManager.compatibilitySettings.matrixCircle },
            set: { networkManager.compatibilitySettings.matrixCircle = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header status
                HStack {
                    StatusDot(active: accessibilityService.isTrusted)
                    Text(
                        accessibilityService.isTrusted
                            ? "System Services Ready" : "Accessibility Permission Needed"
                    )
                    .font(.subheadline)
                    Spacer()
                    if !accessibilityService.isTrusted {
                        Button("Grant Access") {
                            accessibilityService.promptForPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding()
                .background(Material.thin)
                .cornerRadius(10)
                .padding([.horizontal, .top])

                PairingFlowView(securityKey: $securityKey)
                    .padding(.horizontal)

                VStack(alignment: .leading) {
                    Text("Machine Arrangement")
                        .font(.headline)
                        .padding(.leading)

                    MachineMatrixView(
                        machines: $machines,
                        columns: matrixTwoRowBinding.wrappedValue ? 2 : max(1, machines.count)
                    )
                    .frame(height: 200)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Switching")
                        .font(.headline)
                        .padding(.leading)

                    HStack(spacing: 12) {
                        Text("Active: \(networkManager.activeMachineName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(networkManager.switchState.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Material.thin)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(machines) { machine in
                                Button(action: {
                                    networkManager.requestSwitch(to: machine.id)
                                }) {
                                    Label(machine.name, systemImage: "arrow.right.circle")
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Matrix Options")
                        .font(.headline)
                        .padding(.leading)

                    Toggle("Two Row Matrix", isOn: matrixTwoRowBinding)
                        .padding(.horizontal)
                    Toggle("Swap Matrix Order", isOn: matrixSwapBinding)
                        .padding(.horizontal)
                }

                Button(action: {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        networkManager.sendFileDrop(panel.urls)
                    }
                }) {
                    Label("Send Files (MWB DragDrop)", systemImage: "tray.and.arrow.up")
                        .padding(.horizontal)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .navigationTitle("Arrangement")
        .onChange(of: machines) { _, newValue in
            networkManager.updateLocalMatrix(names: newValue.map { $0.name })
            networkManager.sendMachineMatrix(
                names: newValue.map { $0.name },
                twoRow: matrixTwoRowBinding.wrappedValue,
                swap: matrixSwapBinding.wrappedValue
            )
        }
        .onChange(of: networkManager.compatibilitySettings.matrixOneRow) { _, _ in
            networkManager.updateLocalMatrix(names: machines.map { $0.name })
            networkManager.sendMachineMatrix(
                names: machines.map { $0.name },
                twoRow: matrixTwoRowBinding.wrappedValue,
                swap: matrixSwapBinding.wrappedValue
            )
        }
        .onChange(of: networkManager.compatibilitySettings.matrixCircle) { _, _ in
            networkManager.updateLocalMatrix(names: machines.map { $0.name })
            networkManager.sendMachineMatrix(
                names: machines.map { $0.name },
                twoRow: matrixTwoRowBinding.wrappedValue,
                swap: matrixSwapBinding.wrappedValue
            )
        }
    }
}

struct DiscoveredMachinesListView: View {
    var networkManager: MBNetworkManager

    var body: some View {
        List(networkManager.discoveredPeers) { peer in
            HStack {
                Image(systemName: peer.type == .scanned ? "pc" : "laptopcomputer")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading) {
                    Text(peer.name)
                        .font(.headline)
                    Text(String(describing: peer.endpoint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Connect") {
                    networkManager.connect(to: peer.endpoint)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Discovered Machines")
        .overlay {
            if networkManager.discoveredPeers.isEmpty {
                ContentUnderlineView(
                    title: "Scanning for machines...",
                    systemImage: "antenna.radiowaves.left.and.right"
                )
            }
        }
    }
}

struct ContentUnderlineView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}
