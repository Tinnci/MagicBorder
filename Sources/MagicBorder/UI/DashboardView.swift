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

struct DashboardView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBAccessibilityService.self) private var accessibilityService
    @State private var selection: SidebarItem? = .arrangement
    @State private var searchText = ""
    @State private var machines: [Machine] = []
    @State private var showOnboarding = false

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

                Section(localizedString("Machines")) {
                    if self.filteredMachines.isEmpty {
                        ContentUnavailableView.search(text: self.searchText)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(self.filteredMachines) { machine in
                            NavigationLink(destination: MachineDetailView(machineID: machine.id)) {
                                HStack {
                                    Image(
                                        systemName: machine.state == .local
                                            ? "macbook" : (machine.mwbPeerID != nil ? "pc" : "desktopcomputer"))
                                    Text(machine.name)
                                    Spacer()
                                    StatusDot(active: machine.isOnline || machine.state == .local)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(localizedString("MagicBorder"))
            .searchable(
                text: self.$searchText,
                placement: .sidebar,
                prompt: localizedString("Search machines")
            )
            .toolbar {
                ToolbarItem {
                    Button {
                        self.selection = .machines
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help(localizedString("Add Machine"))
                }
                ToolbarItem {
                    Button {
                        self.showOnboarding = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .help(localizedString("Open Setup Assistant..."))
                }
            }
        } detail: {
            if let selection {
                switch selection {
                case .arrangement:
                    ArrangementDetailView(
                        machines: self.$machines,
                        onSelectDiscovered: { self.selection = .machines })
                case .machines:
                    DiscoveredMachinesListView(networkManager: self.networkManager)
                }
            } else {
                Text(localizedString("Select an item from the sidebar"))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 820, minHeight: 620)
        .sheet(isPresented: self.$showOnboarding) {
            OnboardingView()
        }
        .onAppear {
            self.networkManager.applyCompatibilitySettings()
            self.updateMachines()
            if !self.networkManager.compatibilitySettings.onboardingCompleted {
                self.showOnboarding = true
            }
        }
        .onChange(of: self.networkManager.connectedMachines, initial: true) { _, _ in
            self.updateMachines()
        }
        .onChange(of: self.networkManager.arrangement) { _, _ in
            self.updateMachines()
        }
    }

    private func updateMachines() {
        self.machines = self.networkManager.visibleMachines()
    }
}

struct ArrangementDetailView: View {
    @Binding var machines: [Machine]
    var onSelectDiscovered: () -> Void
    @Environment(MBAccessibilityService.self) private var accessibilityService
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager

    @State private var isInspectorPresented = true
    @State private var isFileDropTargeted = false
    @State private var selectedMachineID: UUID?

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
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        if !self.accessibilityService.isTrusted {
                            AccessibilityWarningBanner(service: self.accessibilityService)
                                .padding(.top)
                        }

                        StatusHeaderStrip(
                            networkManager: self.networkManager,
                            activeName: self.networkManager.sessionCoordinator.activeMachineName
                        )
                        .padding(.horizontal)

                        MachineMatrixView(
                            machines: self.$machines,
                            columns: self.matrixTwoRowBinding.wrappedValue ? 2 : max(1, self.machines.count),
                            activeMachineID: self.networkManager.activeMachineId,
                            selectedMachineID: self.selectedMachineID,
                            onSelect: { self.selectedMachineID = $0.id },
                            onSwitch: { machine in
                                if machine.state == .local {
                                    self.networkManager.forceReturnToLocal(reason: "topology-double-click")
                                } else {
                                    self.networkManager.requestSwitch(to: machine.id)
                                }
                            },
                            onSendClipboard: { self.networkManager.pushCurrentClipboard() },
                            onReconnect: { self.networkManager.reconnect(machineId: $0.id) },
                            onDisconnect: { self.networkManager.disconnect(machineId: $0.id) },
                            onAddMachine: self.onSelectDiscovered
                        )
                        .padding(.horizontal)

                        Text(
                            localizedString(
                                "Drag cards to match physical monitor order. Double-click or right-click a card to switch."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .navigationTitle(localizedString("Arrangement"))
        .inspector(isPresented: self.$isInspectorPresented) {
            ArrangementInspector(
                networkManager: networkManager,
                matrixTwoRowBinding: self.matrixTwoRowBinding,
                matrixSwapBinding: self.matrixSwapBinding)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    self.isInspectorPresented.toggle()
                } label: {
                    Label(localizedString("Inspector"), systemImage: "sidebar.right")
                }
            }

            ToolbarItem {
                Button {
                    self.presentFilePickerAndSend()
                } label: {
                    Label(localizedString("Send Files"), systemImage: "square.and.arrow.up")
                }
                .help(localizedString("Send Files via MWB"))
            }

            ToolbarItem {
                SettingsLink {
                    Label(localizedString("Settings"), systemImage: "gear")
                }
                .help(localizedString("Open Settings"))
            }
        }
        .onChange(of: self.machines) { _, newValue in
            networkManager.syncArrangement(
                machineIDs: newValue.map(\.id),
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
        self.networkManager.syncArrangement(
            machineIDs: self.machines.map(\.id),
            twoRow: self.matrixTwoRowBinding.wrappedValue,
            swap: self.matrixSwapBinding.wrappedValue)
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            let urls = await self.extractFileURLs(from: providers)
            guard !urls.isEmpty else { return }
            if self.networkManager.sendFileDrop(urls) {
                self.networkManager.showToast(.filesSent(self.fileSummary(urls)))
            }
        }
        return true
    }

    private func presentFilePickerAndSend() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        if self.networkManager.sendFileDrop(panel.urls) {
            self.networkManager.showToast(.filesSent(self.fileSummary(panel.urls)))
        }
    }

    private func extractFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            if let url = await self.loadURL(from: provider) {
                urls.append(url)
            }
        }
        return Array(Set(urls))
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func fileSummary(_ urls: [URL]) -> String {
        guard let first = urls.first else { return "" }
        return urls.count == 1 ? " \(first.lastPathComponent)" : " \(first.lastPathComponent) +\(urls.count - 1)"
    }
}

private struct StatusHeaderStrip: View {
    var networkManager: MBNetworkManager
    var activeName: String

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(active: !self.networkManager.isInputPaused)
            Text(localizedString("Active: %@", arguments: [self.activeName]))
                .font(.subheadline.weight(.medium))

            Spacer()

            Button {
                self.networkManager.toggleCursorLock()
            } label: {
                Label(
                    self.networkManager.isCursorLocked ? localizedString("Unlock") : localizedString("Lock Screen"),
                    systemImage: self.networkManager.isCursorLocked ? "lock.fill" : "lock.open")
            }
            .controlSize(.small)

            Button {
                self.networkManager.toggleInputPause()
            } label: {
                Label(
                    self.networkManager.isInputPaused ? localizedString("Resume") : localizedString("Pause"),
                    systemImage: self.networkManager.isInputPaused ? "play.fill" : "pause.fill")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct AccessibilityWarningBanner: View {
    let service: MBAccessibilityService

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localizedString("Accessibility Permissions Required"))
                        .font(.headline)
                    Text(localizedString("MagicBorder needs control to share input."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(localizedString("Open System Settings")) {
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
    var matrixTwoRowBinding: Binding<Bool>
    var matrixSwapBinding: Binding<Bool>

    var body: some View {
        @Bindable var sessionCoordinator = self.networkManager.sessionCoordinator

        Form {
            Section(localizedString("Status")) {
                LabeledContent(localizedString("Active Machine"), value: sessionCoordinator.activeMachineName)
                LabeledContent(localizedString("State"), value: sessionCoordinator.switchState.rawValue.capitalized)
                Picker(localizedString("Protocol Mode"), selection: $networkManager.compatibilitySettings.protocolMode)
                {
                    Text(localizedString("Windows (MWB)")).tag(MBProtocolMode.mwbCompatibility)
                    Text(localizedString("Mac-to-Mac")).tag(MBProtocolMode.modern)
                }
            }

            Section(localizedString("Layout Options")) {
                Toggle(localizedString("Two Row Matrix"), isOn: self.matrixTwoRowBinding)
                Toggle(localizedString("Cycle Through Screens"), isOn: self.matrixSwapBinding)
            }

            Section(localizedString("Pairing")) {
                PairingFlowView(securityKey: self.$networkManager.compatibilitySettings.securityKey)
            }

            Section(localizedString("Connected Devices")) {
                if self.networkManager.connectedMachines.isEmpty {
                    Text(localizedString("No devices connected"))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(self.networkManager.connectedMachines) { machine in
                        HStack {
                            Text(machine.name)
                            Spacer()
                            Button(localizedString("Switch")) {
                                self.networkManager.requestSwitch(to: machine.id)
                            }
                            .controlSize(.mini)
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .inspectorColumnWidth(min: 310, ideal: 360, max: 460)
    }
}
