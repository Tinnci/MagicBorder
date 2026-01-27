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
import UniformTypeIdentifiers

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
        if self.searchText.isEmpty {
            self.machines
        } else {
            self.machines.filter { $0.name.localizedStandardContains(self.searchText) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: self.$selection) {
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        NavigationLink(value: item) {
                            Label(item.title, systemImage: item.icon)
                        }
                    }
                }

                Section("Machines") {
                    if self.filteredMachines.isEmpty {
                        ContentUnavailableView.search(text: self.searchText)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(self.filteredMachines) { machine in
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
            }
            .listStyle(.sidebar)
            .navigationTitle("MagicBorder")
            .searchable(text: self.$searchText, placement: .sidebar, prompt: "Search machines")
            .toolbar {
                ToolbarItem {
                    Button(action: { self.selection = .machines }) {
                        Image(systemName: "plus")
                    }
                    .help("Add Machine")
                }
            }
        } detail: {
            if let selection {
                switch selection {
                case .arrangement:
                    ArrangementDetailView(machines: self.$machines)
                case .machines:
                    DiscoveredMachinesListView(networkManager: self.networkManager)
                }
            } else {
                Text("Select an item from the sidebar")
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: self.effectiveOverlayPreferences.position.alignment) {
            if self.dragDropOverlayEnabled, let state = networkManager.dragDropState {
                DragDropOverlayView(
                    state: state,
                    sourceName: self.networkManager.dragDropSourceName,
                    fileSummary: self.networkManager.dragDropFileSummary,
                    progress: self.networkManager.dragDropProgress,
                    showDevice: self.effectiveOverlayPreferences.showDevice,
                    showProgress: self.effectiveOverlayPreferences.showProgress)
                    .scaleEffect(self.effectiveOverlayPreferences.scale)
                    .padding(self.effectiveOverlayPreferences.position.padding)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            self.networkManager.applyCompatibilitySettings()

            // Ensure local machine has stable ID on start
            self.machines = [
                Machine(
                    id: self.localMachineId, name: Host.current().localizedName ?? "Local Mac",
                    isOnline: true),
            ]
        }
        .onChange(of: self.networkManager.compatibilitySettings.securityKey) { _, _ in
            self.networkManager.applyCompatibilitySettings()
        }
        .onChange(of: self.networkManager.connectedMachines, initial: true) { _, connected in
            self.updateMachines(from: connected)
        }
    }

    private func updateMachines(from connected: [MBNetworkManager.ConnectedMachine]) {
        var newMachines = [
            Machine(
                id: localMachineId, name: Host.current().localizedName ?? "Local Mac",
                isOnline: true),
        ]

        for peer in connected {
            newMachines.append(Machine(id: peer.id, name: peer.name, isOnline: true))
        }

        self.machines = newMachines
    }

    private var defaultOverlayPreferences: MBOverlayPreferences {
        let position = MBOverlayPosition(rawValue: dragDropOverlayPosition) ?? .top
        return MBOverlayPreferences(
            showDevice: self.dragDropOverlayShowDevice,
            showProgress: self.dragDropOverlayShowProgress,
            scale: self.dragDropOverlayScale,
            position: position)
    }

    private var effectiveOverlayPreferences: MBOverlayPreferences {
        let deviceName =
            self.networkManager.dragDropSourceName ?? self.networkManager.localDisplayName
        return self.overlayPreferences.preferences(
            for: deviceName, default: self.defaultOverlayPreferences)
    }
}

extension MBOverlayPosition {
    fileprivate var alignment: Alignment {
        switch self {
        case .top: .top
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottom: .bottom
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }

    fileprivate var padding: EdgeInsets {
        switch self {
        case .bottom, .bottomLeading, .bottomTrailing:
            EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16)
        default:
            EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16)
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
                Image(systemName: self.state == .dropping ? "tray.and.arrow.down" : "hand.draw")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(self.state == .dropping ? "Release to drop" : "Dragging files")
                        .font(.headline)
                    if self.showDevice, let sourceName, !sourceName.isEmpty {
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

            if self.showProgress {
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

private struct FileDropZoneView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.up")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Drag files here to send")
                .font(.headline)
            Text("Supports files and folders")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            Color.accentColor.opacity(0.35), lineWidth: 2)))
        .shadow(radius: 12)
        .padding(24)
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
    @State private var isFileDropTargeted = false

    private var matrixTwoRowBinding: Binding<Bool> {
        Binding(
            get: { !self.networkManager.compatibilitySettings.matrixOneRow },
            set: { self.networkManager.compatibilitySettings.matrixOneRow = !$0 })
    }

    private var matrixSwapBinding: Binding<Bool> {
        Binding(
            get: { self.networkManager.compatibilitySettings.matrixCircle },
            set: { self.networkManager.compatibilitySettings.matrixCircle = $0 })
    }

    var body: some View {
        @Bindable var networkManager = networkManager

        VStack(spacing: 0) {
            // Hero Canvas Area
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        if !self.accessibilityService.isTrusted {
                            AccessibilityWarningBanner(service: self.accessibilityService)
                                .padding(.top)
                        }

                        MachineMatrixView(
                            machines: self.$machines,
                            columns: self.matrixTwoRowBinding.wrappedValue
                                ? 2 : max(1, self.machines.count))
                            .padding(.horizontal)

                        Spacer()
                    }
                    .padding(.vertical)
                }
                if self.isFileDropTargeted {
                    FileDropZoneView()
                        .transition(.opacity)
                }
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: self.$isFileDropTargeted) { providers in
            self.handleFileDrop(providers)
        }
        .navigationTitle("Arrangement")
        .inspector(isPresented: self.$isInspectorPresented) {
            ArrangementInspector(
                networkManager: networkManager,
                machines: self.machines,
                matrixTwoRowBinding: self.matrixTwoRowBinding,
                matrixSwapBinding: self.matrixSwapBinding)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { self.isInspectorPresented.toggle() }) {
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
            ToolbarItem {
                SettingsLink {
                    Label("Settings", systemImage: "gear")
                }
                .help("Open Settings")
            }
        }
        .onChange(of: self.machines) { _, newValue in
            networkManager.updateLocalMatrix(names: newValue.map(\.name))
            networkManager.sendMachineMatrix(
                names: newValue.map(\.name),
                twoRow: self.matrixTwoRowBinding.wrappedValue,
                swap: self.matrixSwapBinding.wrappedValue)
        }
        .onChange(of: networkManager.compatibilitySettings.matrixOneRow) { _, _ in
            self.syncMatrix()
        }
        .onChange(of: networkManager.compatibilitySettings.matrixCircle) { _, _ in
            self.syncMatrix()
        }
    }

    private func syncMatrix() {
        self.networkManager.updateLocalMatrix(names: self.machines.map(\.name))
        self.networkManager.sendMachineMatrix(
            names: self.machines.map(\.name),
            twoRow: self.matrixTwoRowBinding.wrappedValue,
            swap: self.matrixSwapBinding.wrappedValue)
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            let urls = await self.extractFileURLs(from: providers)
            guard !urls.isEmpty else { return }
            self.networkManager.sendFileDrop(urls)
            self.networkManager.showToast(
                message: String(localized: "Sent \(self.fileSummary(urls))"),
                systemImage: "tray.and.arrow.up")
        }
        return true
    }

    private func extractFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                continue
            }
            if let url = await self.loadURL(from: provider) {
                urls.append(url)
            }
        }
        return Array(Set(urls))
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil)
                {
                    continuation.resume(returning: url)
                    return
                }
                if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: url)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    private func fileSummary(_ urls: [URL]) -> String {
        guard let first = urls.first else { return "" }
        if urls.count == 1 {
            return " \(first.lastPathComponent)"
        }
        return " \(first.lastPathComponent) +\(urls.count - 1)"
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

                Button("Open System Settings") {
                    self.service.openSystemSettings()
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
                LabeledContent("Active Machine", value: self.networkManager.activeMachineName)
                LabeledContent("State", value: self.networkManager.switchState.rawValue.capitalized)
            }

            Section("Layout Options") {
                Toggle("Two Row Matrix", isOn: self.matrixTwoRowBinding)
                Toggle("Swap Order", isOn: self.matrixSwapBinding)
            }

            Section("Pairing") {
                PairingFlowView(securityKey: self.$networkManager.compatibilitySettings.securityKey)
            }

            Section("Connected Devices") {
                if self.networkManager.connectedMachines.isEmpty {
                    Text("No devices connected")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(self.networkManager.connectedMachines) { machine in
                        HStack {
                            Text(machine.name)
                            Spacer()
                            Button("Switch") {
                                self.networkManager.requestSwitch(to: machine.id)
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
        List(self.networkManager.discoveredPeers) { peer in
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
                    self.networkManager.connect(to: peer.endpoint)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Discovered Machines")
        .overlay {
            if self.networkManager.discoveredPeers.isEmpty {
                ContentUnavailableView(
                    "Scanning for machines...",
                    systemImage: "antenna.radiowaves.left.and.right")
            }
        }
    }
}
