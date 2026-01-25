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
    @Environment(MBOverlayPreferencesStore.self) private var overlayPreferences
    @State private var selection: SidebarItem? = .arrangement
    @State private var searchText = ""
    @AppStorage("dragDropOverlayEnabled") private var dragDropOverlayEnabled = true
    @AppStorage("dragDropOverlayShowDevice") private var dragDropOverlayShowDevice = true
    @AppStorage("dragDropOverlayShowProgress") private var dragDropOverlayShowProgress = true
    @AppStorage("dragDropOverlayScale") private var dragDropOverlayScale = 1.0
    @AppStorage("dragDropOverlayPosition") private var dragDropOverlayPosition = "top"

    // Stable ID for local machine to avoid list flashes
    private let localMachineId = UUID()

    @State private var machines: [Machine] = []

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
                Section {
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
                    Button(action: { selection = .machines }) {
                        Image(systemName: "plus")
                    }
                    .help("Add Machine")
                }
            }
        } detail: {
            if let selection = selection {
                switch selection {
                case .arrangement:
                    ArrangementDetailView(machines: $machines)
                case .machines:
                    DiscoveredMachinesListView(networkManager: networkManager)
                }
            } else {
                Text("Select an item from the sidebar")
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: effectiveOverlayPreferences.position.alignment) {
            if dragDropOverlayEnabled, let state = networkManager.dragDropState {
                DragDropOverlayView(
                    state: state,
                    sourceName: networkManager.dragDropSourceName,
                    fileSummary: networkManager.dragDropFileSummary,
                    progress: networkManager.dragDropProgress,
                    showDevice: effectiveOverlayPreferences.showDevice,
                    showProgress: effectiveOverlayPreferences.showProgress
                )
                .scaleEffect(effectiveOverlayPreferences.scale)
                .padding(effectiveOverlayPreferences.position.padding)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            networkManager.applyCompatibilitySettings()

            // Ensure local machine has stable ID on start
            machines = [
                Machine(
                    id: localMachineId, name: Host.current().localizedName ?? "Local Mac",
                    isOnline: true)
            ]
        }
        .onChange(of: networkManager.compatibilitySettings.securityKey) { _, _ in
            networkManager.applyCompatibilitySettings()
        }
        .onChange(of: networkManager.connectedMachines, initial: true) { _, connected in
            updateMachines(from: connected)
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

    private var defaultOverlayPreferences: MBOverlayPreferences {
        let position = MBOverlayPosition(rawValue: dragDropOverlayPosition) ?? .top
        return MBOverlayPreferences(
            showDevice: dragDropOverlayShowDevice,
            showProgress: dragDropOverlayShowProgress,
            scale: dragDropOverlayScale,
            position: position
        )
    }

    private var effectiveOverlayPreferences: MBOverlayPreferences {
        let deviceName = networkManager.dragDropSourceName ?? networkManager.localDisplayName
        return overlayPreferences.preferences(for: deviceName, default: defaultOverlayPreferences)
    }
}

extension MBOverlayPosition {
    fileprivate var alignment: Alignment {
        switch self {
        case .top: return .top
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottom: return .bottom
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }

    fileprivate var padding: EdgeInsets {
        switch self {
        case .bottom, .bottomLeading, .bottomTrailing:
            return EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16)
        default:
            return EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16)
        }
    }
}

private struct DragDropOverlayView: View {
    let state: MBDragDropState
    let sourceName: String?
    let fileSummary: String?
    let progress: Double?
    let showDevice: Bool
    let showProgress: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: state == .dropping ? "tray.and.arrow.down" : "hand.draw")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state == .dropping ? "松开以投递" : "正在拖拽文件")
                        .font(.headline)
                    if showDevice, let sourceName, !sourceName.isEmpty {
                        Text(sourceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let summary = fileSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showProgress {
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Detail Views

struct ArrangementDetailView: View {
    @Binding var machines: [Machine]
    @Environment(MBAccessibilityService.self) private var accessibilityService:
        MBAccessibilityService
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager:
        MagicBorderKit.MBNetworkManager

    @State private var isInspectorPresented = true

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
        @Bindable var networkManager = networkManager

        VStack(spacing: 0) {
            // Hero Canvas Area
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        if !accessibilityService.isTrusted {
                            AccessibilityWarningBanner(service: accessibilityService)
                                .padding(.top)
                        }

                        MachineMatrixView(
                            machines: $machines,
                            columns: matrixTwoRowBinding.wrappedValue ? 2 : max(1, machines.count)
                        )
                        .padding(.horizontal)

                        Spacer()
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Arrangement")
        .inspector(isPresented: $isInspectorPresented) {
            ArrangementInspector(
                networkManager: networkManager,
                machines: machines,
                matrixTwoRowBinding: matrixTwoRowBinding,
                matrixSwapBinding: matrixSwapBinding
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { isInspectorPresented.toggle() }) {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }

            ToolbarItem {
                Button(action: {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        networkManager.sendFileDrop(panel.urls)
                    }
                }) {
                    Label("Send Files", systemImage: "square.and.arrow.up")
                }
                .help("Send Files via MWB")
            }
        }
        .onChange(of: machines) { _, newValue in
            networkManager.updateLocalMatrix(names: newValue.map { $0.name })
            networkManager.sendMachineMatrix(
                names: newValue.map { $0.name },
                twoRow: matrixTwoRowBinding.wrappedValue,
                swap: matrixSwapBinding.wrappedValue
            )
        }
        .onChange(of: networkManager.compatibilitySettings.matrixOneRow) { _, _ in
            syncMatrix()
        }
        .onChange(of: networkManager.compatibilitySettings.matrixCircle) { _, _ in
            syncMatrix()
        }
    }

    private func syncMatrix() {
        networkManager.updateLocalMatrix(names: machines.map { $0.name })
        networkManager.sendMachineMatrix(
            names: machines.map { $0.name },
            twoRow: matrixTwoRowBinding.wrappedValue,
            swap: matrixSwapBinding.wrappedValue
        )
    }
}

// MARK: - Subviews

struct AccessibilityWarningBanner: View {
    let service: MBAccessibilityService

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Permissions Required")
                        .font(.headline)
                    Text("MagicBorder needs control to share input.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open Settings") {
                    service.promptForPermission()
                }
                .controlSize(.small)
            }
            .padding(4)
        }
        .padding(.horizontal)
    }
}

struct ArrangementInspector: View {
    @Bindable var networkManager: MagicBorderKit.MBNetworkManager
    var machines: [Machine]
    var matrixTwoRowBinding: Binding<Bool>
    var matrixSwapBinding: Binding<Bool>

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Active Machine", value: networkManager.activeMachineName)
                LabeledContent("State", value: networkManager.switchState.rawValue.capitalized)
            }

            Section("Layout Options") {
                Toggle("Two Row Matrix", isOn: matrixTwoRowBinding)
                Toggle("Swap Order", isOn: matrixSwapBinding)
            }

            Section("Pairing") {
                PairingFlowView(securityKey: $networkManager.compatibilitySettings.securityKey)
            }

            Section("Connected Devices") {
                if networkManager.connectedMachines.isEmpty {
                    Text("No devices connected")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(networkManager.connectedMachines) { machine in
                        HStack {
                            Text(machine.name)
                            Spacer()
                            Button("Switch") {
                                networkManager.requestSwitch(to: machine.id)
                            }
                            .controlSize(.mini)
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .inspectorColumnWidth(min: 300, ideal: 350, max: 450)
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
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Discovered Machines")
        .overlay {
            if networkManager.discoveredPeers.isEmpty {
                ContentUnavailableView(
                    "Scanning for machines...",
                    systemImage: "antenna.radiowaves.left.and.right"
                )
            }
        }
    }
}
