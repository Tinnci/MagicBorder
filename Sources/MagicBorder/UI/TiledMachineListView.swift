import MagicBorderKit
import Network
import SwiftUI

enum TiledMachineFilter: String, CaseIterable, Identifiable {
    case all
    case online
    case windows
    case mac
    case saved
    case nearby

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .all: localizedString("All")
        case .online: localizedString("Online")
        case .windows: localizedString("Windows")
        case .mac: localizedString("Mac")
        case .saved: localizedString("Saved")
        case .nearby: localizedString("Nearby")
        }
    }
}

struct TiledMachineListView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(MBOverlayPreferencesStore.self) private var overlayPreferences

    let machines: [Machine]
    var onDiagnoseHost: (String) -> Void
    var onAddMachine: () -> Void

    @State private var activeFilter: TiledMachineFilter = .all
    @State private var inspectedMachineID: UUID?

    private var filteredMachines: [Machine] {
        switch self.activeFilter {
        case .all:
            self.machines
        case .online:
            self.machines.filter { $0.isOnline || $0.state == .local }
        case .windows:
            self.machines.filter { $0.mwbPeerID != nil }
        case .mac:
            self.machines.filter { $0.state == .local || $0.mwbPeerID == nil }
        case .saved, .nearby:
            []
        }
    }

    private var filteredSavedHosts: [SavedHost] {
        let hosts = self.networkManager.savedHosts.hosts
        switch self.activeFilter {
        case .all, .saved:
            return hosts
        case .windows:
            return hosts.filter { $0.protocolMode == .mwbCompatibility }
        case .mac:
            return hosts.filter { $0.protocolMode == .modern }
        case .online, .nearby:
            return []
        }
    }

    private var filteredDiscoveredPeers: [DiscoveredPeer] {
        let peers = self.networkManager.discoveredPeers
        switch self.activeFilter {
        case .all, .nearby:
            return peers
        case .online:
            return peers.filter { self.isPeerConnected($0) }
        case .windows:
            return peers.filter { $0.type == .scanned }
        case .mac:
            return peers.filter { $0.type == .bonjour }
        case .saved:
            return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.filterChipBar()

            if self.filteredMachines.isEmpty, self.filteredSavedHosts.isEmpty, self.filteredDiscoveredPeers.isEmpty {
                ContentUnavailableView(
                    localizedString("No matching machines"),
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(localizedString("Try clearing the active filter or scanning the network."))
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                if !self.filteredMachines.isEmpty {
                    self.sectionHeader(
                        localizedString("Active & Connected"),
                        count: self.filteredMachines.count)
                    LazyVStack(spacing: 8) {
                        ForEach(self.filteredMachines) { machine in
                            self.machineTile(for: machine)
                        }
                    }
                }

                if !self.filteredSavedHosts.isEmpty {
                    self.sectionHeader(
                        localizedString("Saved Hosts"),
                        count: self.filteredSavedHosts.count)
                    LazyVStack(spacing: 8) {
                        ForEach(self.filteredSavedHosts) { host in
                            self.savedHostTile(for: host)
                        }
                    }
                }

                if !self.filteredDiscoveredPeers.isEmpty || self.activeFilter == .nearby {
                    HStack {
                        self.sectionHeader(
                            localizedString("Nearby (Discovered)"),
                            count: self.filteredDiscoveredPeers.count)
                        Spacer()
                        Button {
                            self.networkManager.rescanNetwork()
                        } label: {
                            Label(localizedString("Rescan"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    if self.filteredDiscoveredPeers.isEmpty {
                        Text(localizedString("Scanning for machines..."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(self.filteredDiscoveredPeers) { peer in
                                self.discoveredPeerTile(for: peer)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func filterChipBar() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                AdaptiveGlassContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(TiledMachineFilter.allCases) { filter in
                            let isSelected = self.activeFilter == filter
                            let count = self.count(for: filter)

                            Button {
                                withAnimation(.snappy(duration: 0.16)) {
                                    if filter != .all, isSelected {
                                        self.activeFilter = .all
                                    } else {
                                        self.activeFilter = filter
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(filter.title)
                                        .font(.caption.weight(isSelected ? .semibold : .regular))
                                    Text("\(count)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(
                                            isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.secondary)
                                        )
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(
                                            isSelected ? Color.white.opacity(0.22) : Color.primary.opacity(0.08),
                                            in: Capsule())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .adaptiveGlassPill(
                                    tint: isSelected ? Color.accentColor.opacity(0.85) : nil,
                                    interactive: true
                                )
                                .foregroundStyle(isSelected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 8)

                Button(action: self.onAddMachine) {
                    Label(localizedString("Pair"), systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func machineTile(for machine: Machine) -> some View {
        let isLocal = machine.state == .local
        let hasRemotePeers = self.machines.count > 1
        let isFocused =
            hasRemotePeers
            && ((self.networkManager.activeMachineId == nil && isLocal)
                || (self.networkManager.activeMachineId == machine.id))
        let telemetry = self.networkManager.peerTelemetry[machine.id]
        let hasInputOverride = !isLocal && self.networkManager.peerProfiles.hasOverride(for: machine.name)
        let hasOverlayOverride = self.overlayPreferences.hasOverride(for: machine.name)

        HStack(spacing: 12) {
            Image(systemName: isLocal ? "macbook" : (machine.mwbPeerID != nil ? "pc" : "desktopcomputer"))
                .font(.title3)
                .foregroundStyle(isFocused || machine.isOnline || isLocal ? Color.accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    StatusDot(active: machine.isOnline || isLocal)
                    Text(machine.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if isFocused {
                        Text(localizedString("Controlling"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }

                    if let rtt = telemetry?.rttMs {
                        Text("\(rtt) ms")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }

                    if hasInputOverride {
                        Text(localizedString("Custom Input"))
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }

                    if hasOverlayOverride {
                        Text(localizedString("Overlay"))
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }
                }

                Text(self.machineSubtitle(machine: machine, isLocal: isLocal))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(isLocal ? localizedString("Local") : localizedString("Switch")) {
                    if isLocal {
                        self.networkManager.forceReturnToLocal(reason: "tiled-list")
                    } else {
                        self.networkManager.requestSwitch(to: machine.id)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(
                    (!isLocal && !machine.isOnline)
                        || isFocused
                        || (isLocal && self.networkManager.activeMachineId == nil))

                Button {
                    self.inspectedMachineID = machine.id
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(localizedString("Inspect Machine"))

                if !isLocal {
                    Button {
                        self.networkManager.reconnect(machineId: machine.id)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(localizedString("Restart Connection"))

                    Button(role: .destructive) {
                        self.networkManager.disconnect(machineId: machine.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(localizedString("Disconnect"))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isFocused ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isFocused ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2),
                            lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if isLocal {
                self.networkManager.forceReturnToLocal(reason: "tiled-double-click")
            } else {
                self.networkManager.requestSwitch(to: machine.id)
            }
        }
        .onTapGesture {
            self.inspectedMachineID = machine.id
        }
        .popover(
            isPresented: Binding(
                get: { self.inspectedMachineID == machine.id },
                set: { presented in
                    if !presented, self.inspectedMachineID == machine.id {
                        self.inspectedMachineID = nil
                    }
                }),
            arrowEdge: .trailing
        ) {
            MachineInspectorPopover(machineID: machine.id) { host in
                self.inspectedMachineID = nil
                self.onDiagnoseHost(host)
            }
        }
    }

    @ViewBuilder
    private func savedHostTile(for host: SavedHost) -> some View {
        HStack(spacing: 12) {
            Image(systemName: host.protocolMode == .mwbCompatibility ? "pc" : "desktopcomputer")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(host.name)
                        .font(.subheadline.weight(.semibold))
                    Text(host.protocolMode == .mwbCompatibility ? "MWB" : localizedString("Mac-to-Mac"))
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Text("\(host.address):\(host.messagePort)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Button(localizedString("Connect")) {
                    self.networkManager.compatibilitySettings.protocolMode = host.protocolMode
                    self.networkManager.applyCompatibilitySettings()
                    self.networkManager.connectToHost(ip: host.address, port: host.messagePort)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(localizedString("Diagnose")) {
                    self.onDiagnoseHost(host.address)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    self.networkManager.savedHosts.remove(id: host.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(localizedString("Remove"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)))
    }

    @ViewBuilder
    private func discoveredPeerTile(for peer: DiscoveredPeer) -> some View {
        let isConnected = self.isPeerConnected(peer)

        HStack(spacing: 12) {
            Image(systemName: peer.type == .scanned ? "pc" : "laptopcomputer")
                .font(.title3)
                .foregroundStyle(isConnected ? .green : Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.name)
                    .font(.subheadline.weight(.semibold))
                Text(Self.formattedEndpoint(peer.endpoint))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isConnected {
                Label(localizedString("Connected"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button(localizedString("Connect")) {
                    self.networkManager.connect(to: peer.endpoint)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)))
    }

    private func isPeerConnected(_ peer: DiscoveredPeer) -> Bool {
        self.networkManager.connectedMachines.contains {
            $0.name.caseInsensitiveCompare(peer.name) == .orderedSame
        }
    }

    private func count(for filter: TiledMachineFilter) -> Int {
        switch filter {
        case .all:
            self.machines.count + self.networkManager.savedHosts.hosts.count + self.networkManager.discoveredPeers.count
        case .online:
            self.machines.filter { $0.isOnline || $0.state == .local }.count
                + self.networkManager.discoveredPeers.filter { self.isPeerConnected($0) }.count
        case .windows:
            self.machines.filter { $0.mwbPeerID != nil }.count
                + self.networkManager.savedHosts.hosts.filter { $0.protocolMode == .mwbCompatibility }.count
                + self.networkManager.discoveredPeers.filter { $0.type == .scanned }.count
        case .mac:
            self.machines.filter { $0.state == .local || $0.mwbPeerID == nil }.count
                + self.networkManager.savedHosts.hosts.filter { $0.protocolMode == .modern }.count
                + self.networkManager.discoveredPeers.filter { $0.type == .bonjour }.count
        case .saved:
            self.networkManager.savedHosts.hosts.count
        case .nearby:
            self.networkManager.discoveredPeers.count
        }
    }

    private func machineSubtitle(machine: Machine, isLocal: Bool) -> String {
        if isLocal {
            return localizedString("This Mac")
        }
        let modeText =
            machine.mwbPeerID != nil ? localizedString("Windows (MWB)") : localizedString("Mac-to-Mac")
        let sizeText =
            machine.screenSize != .zero ? " • \(Int(machine.screenSize.width))×\(Int(machine.screenSize.height))" : ""
        return modeText + sizeText
    }

    private static func formattedEndpoint(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, let port):
            "\(host):\(port.rawValue)"
        case .service(let name, _, _, _):
            "\(name) (Bonjour)"
        default:
            String(describing: endpoint)
        }
    }
}
