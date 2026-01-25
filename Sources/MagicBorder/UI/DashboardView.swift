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
import Observation
import SwiftUI

// MARK: - Sidebar Item

enum SidebarItem: String, CaseIterable, Identifiable {
    case arrangement
    case settings
    case machines
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .arrangement: return "Arrangement"
        case .settings: return "Settings"
        case .machines: return "Discovered Machines"
        }
    }
    
    var icon: String {
        switch self {
        case .arrangement: return "square.grid.2x2"
        case .settings: return "gearshape"
        case .machines: return "laptopcomputer.and.iphone"
        }
    }
}

// MARK: - Subviews

private struct StatusDot: View {
    var active: Bool
    var body: some View {
        Circle()
            .fill(active ? Color.green : Color.red)
            .frame(width: 8, height: 8)
            .shadow(color: (active ? Color.green : Color.red).opacity(0.5), radius: 2)
    }
}

struct MachineDetailView: View {
    let machine: Machine
    
    private let columns = [
        GridItem(.adaptive(minimum: 70))
    ]
    
    @State private var isRefreshing = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Machine Info Header
                    HStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 80, height: 80)
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue.gradient)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(machine.name)
                                .font(.title)
                                .fontWeight(.bold)
                            HStack {
                                StatusDot(active: machine.isOnline)
                                Text(machine.isOnline ? "Online" : "Offline")
                                    .foregroundStyle(machine.isOnline ? .green : .secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
                    
                    Divider()
                    
                    // Pinned Programs Grid
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pinned Programs")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(0..<8) { i in
                                ProgramIconButton(name: "App \(i+1)", icon: "app.dashed")
                            }
                        }
                    }
                    .padding()
                    
                    // Quick Links / Configuration
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Configuration")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        GroupBox {
                            VStack(spacing: 0) {
                                NavigationLink(destination: Text("Display Settings Content")) {
                                    LinkRow(title: "Display Settings", icon: "display")
                                }
                                Divider()
                                NavigationLink(destination: Text("Input Configuration Content")) {
                                    LinkRow(title: "Input Configuration", icon: "keyboard")
                                }
                            }
                        }
                    }
                    .padding()
                }
                .padding()
            }
            
            // Bottom Toolbar Divider
            Divider()
            
            HStack {
                Button(action: {}) {
                    Label("Restart", systemImage: "restart")
                }
                .buttonStyle(.plain)
                .help("Restart connection")
                
                Button(action: {}) {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
                .help("Disconnect machine")
                
                Spacer()
                
                Button(action: {
                    isRefreshing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        isRefreshing = false
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.plain)
                .help("Refresh Status")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Material.bar)
        }
        .navigationTitle(machine.name)
    }
}

private struct ProgramIconButton: View {
    let name: String
    let icon: String
    @State private var isHovering = false
    
    var body: some View {
        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.1) : Color.primary.opacity(0.05))
                    .frame(width: 60, height: 60)
                
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            Text(name)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .onHover { isHovering = $0 }
        .onTapGesture {
            // Mock animation for app launch
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                // scale effect could be added
            }
        }
    }
}

private struct LinkRow: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
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
    
    @State private var selection: SidebarItem? = .arrangement
    @State private var searchText = ""
    @State private var isRefreshing = false

    @State private var machines: [Machine] = [
        Machine(id: UUID(), name: Host.current().localizedName ?? "Local Mac", isOnline: true)
    ]

    @SceneStorage("securityKey") private var securityKey: String = "YOUR_SECURE_KEY_123"

    var filteredMachines: [Machine] {
        if searchText.isEmpty {
            return machines
        } else {
            return machines.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                    Button(action: { /* Add machine action */ }) {
                        Image(systemName: "plus")
                    }
                    .help("Add Machine")
                }
                        ToolbarItem {
                            Button(action: {
                                isRefreshing = true
                                // Simulate a refresh
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    isRefreshing = false
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                    .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
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
        }
        .onChange(of: securityKey) { _, newValue in
            networkManager.securityKey = newValue
        }
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

// MARK: - Detail Views

struct ArrangementDetailView: View {
    @Binding var machines: [Machine]
    @Binding var securityKey: String
    @Environment(MBAccessibilityService.self) private var accessibilityService: MBAccessibilityService
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager:
        MagicBorderKit.MBNetworkManager

    @State private var matrixTwoRow = false
    @State private var matrixSwap = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header status
                HStack {
                    StatusDot(active: accessibilityService.isTrusted)
                    Text(accessibilityService.isTrusted ? "System Services Ready" : "Accessibility Permission Needed")
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

                VStack(alignment: .leading) {
                    Text("Machine Arrangement")
                        .font(.headline)
                        .padding(.leading)

                    MachineMatrixView(machines: $machines)
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
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Matrix Options")
                        .font(.headline)
                        .padding(.leading)

                    Toggle("Two Row Matrix", isOn: $matrixTwoRow)
                        .padding(.horizontal)
                    Toggle("Swap Matrix Order", isOn: $matrixSwap)
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
                
                PairingCardView(securityKey: $securityKey)
                    .padding(.horizontal)
                
                Spacer()
            }
        }
        .navigationTitle("Arrangement")
        .onChange(of: machines) { _, newValue in
            networkManager.sendMachineMatrix(names: newValue.map { $0.name }, twoRow: matrixTwoRow, swap: matrixSwap)
        }
        .onChange(of: matrixTwoRow) { _, _ in
            networkManager.sendMachineMatrix(names: machines.map { $0.name }, twoRow: matrixTwoRow, swap: matrixSwap)
        }
        .onChange(of: matrixSwap) { _, _ in
            networkManager.sendMachineMatrix(names: machines.map { $0.name }, twoRow: matrixTwoRow, swap: matrixSwap)
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
