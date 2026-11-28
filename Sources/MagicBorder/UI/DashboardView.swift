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
    @Environment(MBOverlayPreferencesStore.self) private var overlayPreferences

    @AppStorage("ui.dashboardMode") private var viewMode = "field"
    @State private var machines: [Machine] = []
    @State private var isFileDropTargeted = false
    @State private var showOnboarding = false
    @State private var showDoctor = false
    @State private var doctorInitialHost = ""
    @State private var showPairingPopover = false
    @State private var showEdgePopover = false
    @State private var showClipboardPopover = false
    @State private var showEscapePopover = false
    @State private var isNearbyRailExpanded = true
    @State private var copiedLocalIP = false

    private var hasConnectedPeers: Bool {
        !self.networkManager.connectedMachines.isEmpty
    }

    private var isTwoRow: Bool {
        !self.networkManager.compatibilitySettings.matrixOneRow
    }

    private var isSwap: Bool {
        self.networkManager.compatibilitySettings.matrixCircle
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !self.accessibilityService.isTrusted {
                        AccessibilityWarningBanner(service: self.accessibilityService)
                            .padding(.top, 4)
                    }

                    self.fieldCommandStrip()

                    if self.viewMode == "list" {
                        TiledMachineListView(
                            machines: self.machines,
                            onDiagnoseHost: { host in self.openDoctor(host: host) },
                            onAddMachine: { self.showPairingPopover = true })
                    } else {
                        SpatialArrangementView(
                            machines: self.$machines,
                            twoRow: self.isTwoRow,
                            activeMachineID: self.networkManager.activeMachineId,
                            telemetryByID: self.networkManager.peerTelemetry,
                            peerProfiles: self.networkManager.peerProfiles,
                            overlayPreferences: self.overlayPreferences,
                            edgeSettings: self.networkManager.compatibilitySettings,
                            isInputPaused: self.networkManager.isInputPaused,
                            isCursorLocked: self.networkManager.isCursorLocked,
                            onSwitch: { machine in
                                if machine.state == .local {
                                    self.networkManager.forceReturnToLocal(reason: "field-double-click")
                                } else {
                                    self.networkManager.requestSwitch(to: machine.id)
                                }
                            },
                            onSendClipboard: { self.networkManager.pushCurrentClipboard() },
                            onReconnect: { self.networkManager.reconnect(machineId: $0.id) },
                            onDisconnect: { self.networkManager.disconnect(machineId: $0.id) },
                            onDiagnoseHost: { host in self.openDoctor(host: host) },
                            onAddMachine: { self.showPairingPopover = true })

                        Text(
                            localizedString(
                                "Click a display to inspect & tune. Click a border to edit edge rules. Drag to reorder."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        self.nearbyAndSavedRail()
                    }
                }
                .padding(16)
            }

            if self.isFileDropTargeted,
                self.hasConnectedPeers,
                self.networkManager.protocolMode == .mwbCompatibility,
                self.networkManager.compatibilitySettings.transferFiles
            {
                FileDropZoneView()
                    .transition(.opacity)
            }
        }
        .background {
            VStack {
                Button("") { self.viewMode = "field" }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { self.viewMode = "list" }
                    .keyboardShortcut("2", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .frame(minWidth: 700, minHeight: 540)
        .navigationTitle(localizedString("MagicBorder"))
        .onDrop(of: [UTType.fileURL], isTargeted: self.$isFileDropTargeted) { providers in
            self.handleFileDrop(providers)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(localizedString("View"), selection: self.$viewMode) {
                    Label(localizedString("Field"), systemImage: "rectangle.3.group").tag("field")
                    Label(localizedString("Tiled List"), systemImage: "list.bullet.rectangle").tag("list")
                }
                .pickerStyle(.segmented)
                .frame(width: 196)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    self.showPairingPopover.toggle()
                } label: {
                    Label(localizedString("Add Machine"), systemImage: "plus")
                }
                .help(localizedString("Pair a Machine"))

                Button {
                    self.presentFilePickerAndSend()
                } label: {
                    Label(localizedString("Send Files"), systemImage: "square.and.arrow.up")
                }
                .help(localizedString("Send Files via MWB"))
                .disabled(!self.hasConnectedPeers || self.networkManager.protocolMode == .modern)

                Button {
                    self.openDoctor(host: self.networkManager.savedHosts.hosts.first?.address ?? "")
                } label: {
                    Label(localizedString("Connection Doctor"), systemImage: "stethoscope")
                }
                .help(localizedString("Run Connection Doctor..."))

                Button {
                    self.showOnboarding = true
                } label: {
                    Label(localizedString("Setup Guide"), systemImage: "sparkles")
                }
                .help(localizedString("Open Setup Assistant..."))

                SettingsLink {
                    Label(localizedString("Settings"), systemImage: "gear")
                }
                .help(localizedString("Open Settings"))
            }
        }
        .sheet(isPresented: self.$showOnboarding) {
            OnboardingView()
        }
        .sheet(isPresented: self.$showDoctor) {
            ConnectionDoctorView(initialHost: self.doctorInitialHost)
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
        .onChange(of: self.machines) { _, newValue in
            self.networkManager.syncArrangement(
                machineIDs: newValue.map(\.id),
                twoRow: self.isTwoRow,
                swap: self.isSwap)
        }
        .onChange(of: self.networkManager.compatibilitySettings.matrixOneRow) { _, _ in
            self.syncMatrix()
        }
        .onChange(of: self.networkManager.compatibilitySettings.matrixCircle) { _, _ in
            self.syncMatrix()
        }
    }

    @ViewBuilder
    private func fieldCommandStrip() -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                StatusDot(active: self.hasConnectedPeers && !self.networkManager.isInputPaused)
                Text(
                    self.hasConnectedPeers
                        ? localizedString(
                            "Active: %@",
                            arguments: [self.networkManager.sessionCoordinator.activeMachineName])
                        : localizedString("No devices connected")
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(self.hasConnectedPeers ? .primary : .secondary)
                .lineLimit(1)
            }

            Divider()
                .frame(height: 16)

            AdaptiveGlassContainer(spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        self.showPairingPopover.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(self.isPairingKeyReady ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(
                                self.networkManager.compatibilitySettings.protocolMode == .mwbCompatibility
                                    ? "MWB" : localizedString("Mac-to-Mac")
                            )
                            .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .adaptiveGlassPill(interactive: true)
                    }
                    .buttonStyle(.plain)
                    .help(localizedString("Protocol & Pairing"))
                    .popover(isPresented: self.$showPairingPopover, arrowEdge: .bottom) {
                        ProtocolAndPairingPopover()
                    }

                    Button {
                        self.showEdgePopover.toggle()
                    } label: {
                        Label(self.edgePillTitle, systemImage: "arrow.left.arrow.right")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .adaptiveGlassPill(interactive: true)
                    }
                    .buttonStyle(.plain)
                    .help(localizedString("Configure Edge Crossing"))
                    .popover(isPresented: self.$showEdgePopover, arrowEdge: .bottom) {
                        EdgeBehaviorPopover()
                    }

                    Button {
                        self.showClipboardPopover.toggle()
                    } label: {
                        Label(self.clipboardPillTitle, systemImage: "doc.on.clipboard")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .adaptiveGlassPill(interactive: true)
                    }
                    .buttonStyle(.plain)
                    .help(localizedString("Clipboard & Privacy"))
                    .popover(isPresented: self.$showClipboardPopover, arrowEdge: .bottom) {
                        ClipboardQuickPopover()
                    }

                    Button {
                        self.showEscapePopover.toggle()
                    } label: {
                        Label(self.escapePillTitle, systemImage: "escape")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .adaptiveGlassPill(interactive: true)
                    }
                    .buttonStyle(.plain)
                    .help(localizedString("Escape & Global Hotkeys"))
                    .popover(isPresented: self.$showEscapePopover, arrowEdge: .bottom) {
                        EscapeQuickPopover()
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                self.networkManager.toggleCursorLock()
            } label: {
                Label(
                    self.networkManager.isCursorLocked ? localizedString("Unlock") : localizedString("Lock Screen"),
                    systemImage: self.networkManager.isCursorLocked ? "lock.fill" : "lock.open")
            }
            .controlSize(.small)
            .disabled(!self.hasConnectedPeers && !self.networkManager.isCursorLocked)

            Button {
                self.networkManager.toggleInputPause()
            } label: {
                Label(
                    self.networkManager.isInputPaused ? localizedString("Resume") : localizedString("Pause"),
                    systemImage: self.networkManager.isInputPaused ? "play.fill" : "pause.fill")
            }
            .controlSize(.small)
            .disabled(!self.hasConnectedPeers && !self.networkManager.isInputPaused)

            Button {
                self.networkManager.lockAllScreens()
            } label: {
                Label(localizedString("Lock All"), systemImage: "lock.shield")
            }
            .controlSize(.small)
            .disabled(!self.hasConnectedPeers)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func nearbyAndSavedRail() -> some View {
        let savedHosts = self.networkManager.savedHosts.hosts
        let discovered = self.networkManager.discoveredPeers
        let localIP = self.networkManager.localIPv4Addresses().first

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        self.isNearbyRailExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: self.isNearbyRailExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(localizedString("Nearby & Saved"))
                            .font(.subheadline.weight(.semibold))
                        Text("\(savedHosts.count + discovered.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .buttonStyle(.plain)

                if let localIP {
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(localIP, forType: .string)
                        self.copiedLocalIP = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.5))
                            self.copiedLocalIP = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: self.copiedLocalIP ? "checkmark" : "wifi")
                                .font(.caption2)
                            Text(localIP)
                                .font(.caption.monospaced())
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.55), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(localizedString("Copy"))
                }

                Spacer()

                Button {
                    self.networkManager.rescanNetwork()
                } label: {
                    Label(localizedString("Rescan"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button {
                    self.showPairingPopover = true
                } label: {
                    Label(localizedString("Pair"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }

            if self.isNearbyRailExpanded {
                if savedHosts.isEmpty && discovered.isEmpty {
                    Text(localizedString("No saved or discovered machines yet. Click Pair to add one by IP."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(savedHosts) { host in
                                Button {
                                    self.networkManager.compatibilitySettings.protocolMode = host.protocolMode
                                    self.networkManager.applyCompatibilitySettings()
                                    self.networkManager.connectToHost(ip: host.address, port: host.messagePort)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(
                                            systemName: host.protocolMode == .mwbCompatibility
                                                ? "pc" : "desktopcomputer"
                                        )
                                        .font(.caption)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(host.name)
                                                .font(.caption.weight(.medium))
                                            Text(host.address)
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(localizedString("Connect")) {
                                        self.networkManager.compatibilitySettings.protocolMode = host.protocolMode
                                        self.networkManager.applyCompatibilitySettings()
                                        self.networkManager.connectToHost(ip: host.address, port: host.messagePort)
                                    }
                                    Button(localizedString("Diagnose")) {
                                        self.openDoctor(host: host.address)
                                    }
                                    Divider()
                                    Button(localizedString("Remove"), role: .destructive) {
                                        self.networkManager.savedHosts.remove(id: host.id)
                                    }
                                }
                            }

                            ForEach(discovered) { peer in
                                let isConnected = self.networkManager.connectedMachines.contains {
                                    $0.name.caseInsensitiveCompare(peer.name) == .orderedSame
                                }
                                Button {
                                    if !isConnected {
                                        self.networkManager.connect(to: peer.endpoint)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: peer.type == .scanned ? "pc" : "laptopcomputer")
                                            .font(.caption)
                                            .foregroundStyle(isConnected ? .green : Color.accentColor)
                                        Text(peer.name)
                                            .font(.caption.weight(.medium))
                                        if isConnected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .disabled(isConnected)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 12))
    }

    private var isPairingKeyReady: Bool {
        let trimmed = self.networkManager.compatibilitySettings.securityKey.replacingOccurrences(of: " ", with: "")
        return self.networkManager.compatibilitySettings.protocolMode == .modern || trimmed.count >= 16
    }

    private var edgePillTitle: String {
        let settings = self.networkManager.compatibilitySettings
        if !settings.switchByMouse {
            return localizedString("Edge: Off")
        }
        switch settings.edgeCrossingModifier {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .none:
            if settings.edgeDwellSeconds > 0 {
                return "\(Int((settings.edgeDwellSeconds * 1000).rounded()))ms"
            }
            return localizedString("Edge: Free")
        }
    }

    private var clipboardPillTitle: String {
        let settings = self.networkManager.compatibilitySettings
        guard settings.shareClipboard else {
            return localizedString("Clip: Off")
        }
        return settings.ignoreConcealedClipboard ? localizedString("Clip: Safe") : localizedString("Clip: On")
    }

    private var escapePillTitle: String {
        switch self.networkManager.compatibilitySettings.escapeMode {
        case .doubleTapEsc: "Esc ×2"
        case .controlOptionEsc: "⌃⌥⎋"
        case .singleEsc: "Esc ×1"
        }
    }

    private func openDoctor(host: String) {
        self.doctorInitialHost = host
        self.showDoctor = true
    }

    private func updateMachines() {
        self.machines = self.networkManager.visibleMachines()
    }

    private func syncMatrix() {
        self.networkManager.syncArrangement(
            machineIDs: self.machines.map(\.id),
            twoRow: self.isTwoRow,
            swap: self.isSwap)
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
    }
}
