import AppKit
import MagicBorderKit
import SwiftUI
import UniformTypeIdentifiers

struct SpatialArrangementView: View {
    @Binding var machines: [Machine]
    let twoRow: Bool
    let activeMachineID: UUID?
    let telemetryByID: [UUID: PeerTelemetry]
    let peerProfiles: MBPeerProfileStore
    let overlayPreferences: MBOverlayPreferencesStore
    let edgeSettings: MBCompatibilitySettings
    let isInputPaused: Bool
    let isCursorLocked: Bool
    var onSwitch: (Machine) -> Void
    var onSendClipboard: () -> Void
    var onReconnect: (Machine) -> Void
    var onDisconnect: (Machine) -> Void
    var onDiagnoseHost: (String) -> Void
    var onAddMachine: () -> Void

    @State private var inspectedMachineID: UUID?
    @State private var activeSeamID: String?
    @State private var draggingMachine: Machine?
    @State private var hoveredDropID: UUID?

    var body: some View {
        let columns = self.twoRow ? 2 : max(1, self.machines.count)
        let rows = self.machines.chunked(into: max(1, columns))

        VStack(spacing: 16) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(alignment: .center, spacing: 12) {
                    ForEach(Array(rows[rowIndex].enumerated()), id: \.element.id) { colIndex, machine in
                        self.displayNode(for: machine)
                        if colIndex < rows[rowIndex].count - 1 {
                            self.seamButton(
                                id: "h-\(rowIndex)-\(colIndex)",
                                systemImage: "arrow.left.arrow.right")
                        }
                    }

                    if rows.count == 1, rows[rowIndex].count == 1 {
                        self.seamButton(
                            id: "h-add-slot",
                            systemImage: "arrow.left.arrow.right")
                        self.addMachineSlotTile()
                    }
                }

                if rowIndex < rows.count - 1 {
                    HStack(spacing: 28) {
                        ForEach(0..<rows[rowIndex].count, id: \.self) { colIndex in
                            self.seamButton(
                                id: "v-\(rowIndex)-\(colIndex)",
                                systemImage: "arrow.up.arrow.down")
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
        .animation(.default, value: self.machines)
    }

    @ViewBuilder
    private func displayNode(for machine: Machine) -> some View {
        let isLocal = machine.state == .local
        let hasRemotePeers = self.machines.count > 1
        let isFocused =
            hasRemotePeers && ((self.activeMachineID == nil && isLocal) || (self.activeMachineID == machine.id))
        let resolution = Self.effectiveResolution(for: machine)
        let boxSize = Self.scaledDisplaySize(for: resolution)
        let telemetry = self.telemetryByID[machine.id]
        let hasInputOverride = !isLocal && self.peerProfiles.hasOverride(for: machine.name)
        let hasOverlayOverride = self.overlayPreferences.hasOverride(for: machine.name)
        let isDropHighlighted = self.hoveredDropID == machine.id && self.draggingMachine != machine
        let isInspected = self.inspectedMachineID == machine.id

        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(
                        isFocused
                            ? Color.accentColor.opacity(0.16)
                            : (isInspected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(
                                isDropHighlighted || isFocused
                                    ? Color.accentColor
                                    : (isInspected ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.35)),
                                lineWidth: isFocused || isDropHighlighted ? 2 : 1.25))

                VStack(spacing: 4) {
                    Image(systemName: isLocal ? "macbook" : (machine.mwbPeerID != nil ? "pc" : "desktopcomputer"))
                        .font(.title2)
                        .foregroundStyle(isFocused || machine.isOnline || isLocal ? Color.accentColor : .secondary)

                    Text(machine.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text("\(Int(resolution.width))×\(Int(resolution.height))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            .frame(width: boxSize.width, height: boxSize.height)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    StatusDot(active: machine.isOnline || isLocal)
                    if hasInputOverride {
                        Image(systemName: "keyboard")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .help(localizedString("Per-Peer Input Profile"))
                    }
                    if hasOverlayOverride {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .help(localizedString("Per-Device Override"))
                    }
                }
                .padding(7)
            }
            .overlay(alignment: .topTrailing) {
                if let rtt = telemetry?.rttMs {
                    Text("\(rtt) ms")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .adaptiveGlass(in: Capsule())
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 28, height: 3)
                    .offset(y: 6)
            }

            if isLocal, NSScreen.screens.count > 1 {
                Text(localizedString("%d Local Displays", arguments: [NSScreen.screens.count]))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if isFocused {
                Text(localizedString("Controlling"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Text(isLocal ? localizedString("This Mac") : localizedString("Click to inspect"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            self.onSwitch(machine)
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
            arrowEdge: .bottom
        ) {
            MachineInspectorPopover(machineID: machine.id) { host in
                self.inspectedMachineID = nil
                self.onDiagnoseHost(host)
            }
        }
        .contextMenu {
            Button(localizedString("Inspect Machine")) {
                self.inspectedMachineID = machine.id
            }
            Button(isLocal ? localizedString("Return Control Here") : localizedString("Switch to Machine")) {
                self.onSwitch(machine)
            }
            if !isLocal {
                Button(localizedString("Send Clipboard Now")) {
                    self.onSendClipboard()
                }
                Button(localizedString("Restart Connection")) {
                    self.onReconnect(machine)
                }
                Divider()
                Button(localizedString("Disconnect"), role: .destructive) {
                    self.onDisconnect(machine)
                }
            }
        }
        .onDrag {
            self.draggingMachine = machine
            return NSItemProvider(object: machine.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: SpatialMachineDropDelegate(
                item: machine,
                machines: self.$machines,
                draggingItem: self.$draggingMachine,
                hoveredID: self.$hoveredDropID))
    }

    @ViewBuilder
    private func addMachineSlotTile() -> some View {
        let size = Self.scaledDisplaySize(for: CGSize(width: 1920, height: 1080))
        Button(action: self.onAddMachine) {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.dashed")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text(localizedString("Pair a Machine"))
                    .font(.caption.weight(.semibold))
                Text(localizedString("Click to discover or enter an IP"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(width: size.width, height: size.height)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(.secondary.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func seamButton(id: String, systemImage: String) -> some View {
        Button {
            self.activeSeamID = id
        } label: {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))

                if self.isCursorLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                } else if !self.edgeSettings.switchByMouse || self.isInputPaused {
                    Image(systemName: "nosign")
                        .font(.system(size: 8))
                } else if let modifierSymbol = self.modifierBadge {
                    Text(modifierSymbol)
                        .font(.caption2.weight(.bold))
                } else if self.edgeSettings.edgeDwellSeconds > 0 {
                    Text("\(Int((self.edgeSettings.edgeDwellSeconds * 1000).rounded()))ms")
                        .font(.system(size: 9).monospacedDigit())
                }
            }
            .foregroundStyle(self.seamTint)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .adaptiveGlassPill(
                tint: self.activeSeamID == id ? Color.accentColor.opacity(0.22) : nil,
                interactive: true)
        }
        .buttonStyle(.plain)
        .help(localizedString("Configure Edge Crossing"))
        .accessibilityLabel(localizedString("Configure Edge Crossing"))
        .popover(
            isPresented: Binding(
                get: { self.activeSeamID == id },
                set: { presented in
                    if !presented, self.activeSeamID == id {
                        self.activeSeamID = nil
                    }
                }),
            arrowEdge: .bottom
        ) {
            EdgeBehaviorPopover()
        }
    }

    private var modifierBadge: String? {
        switch self.edgeSettings.edgeCrossingModifier {
        case .none: nil
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        }
    }

    private var seamTint: Color {
        if self.isCursorLocked || !self.edgeSettings.switchByMouse || self.isInputPaused {
            return .orange
        }
        if self.edgeSettings.edgeCrossingModifier != .none || self.edgeSettings.edgeDwellSeconds > 0 {
            return .accentColor
        }
        return .secondary
    }

    private static func effectiveResolution(for machine: Machine) -> CGSize {
        if machine.screenSize != .zero {
            return machine.screenSize
        }
        if machine.state == .local, let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame {
            return frame.size
        }
        return CGSize(width: 1920, height: 1080)
    }

    private static func scaledDisplaySize(for resolution: CGSize) -> CGSize {
        let ratio = max(0.8, min(2.4, resolution.width / max(1, resolution.height)))
        let baseHeight: CGFloat = 108
        return CGSize(width: min(230, max(124, baseHeight * ratio)), height: baseHeight)
    }
}

private struct SpatialMachineDropDelegate: DropDelegate {
    let item: Machine
    @Binding var machines: [Machine]
    @Binding var draggingItem: Machine?
    @Binding var hoveredID: UUID?

    func dropEntered(info _: DropInfo) {
        self.hoveredID = self.item.id
    }

    func dropExited(info _: DropInfo) {
        if self.hoveredID == self.item.id {
            self.hoveredID = nil
        }
    }

    func performDrop(info _: DropInfo) -> Bool {
        self.hoveredID = nil
        if let draggingItem, self.item != draggingItem,
            let from = self.machines.firstIndex(of: draggingItem),
            let to = self.machines.firstIndex(of: self.item)
        {
            withAnimation {
                self.machines.move(
                    fromOffsets: IndexSet(integer: from),
                    toOffset: to > from ? to + 1 : to)
            }
        }
        self.draggingItem = nil
        return true
    }
}

extension Array {
    fileprivate func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
