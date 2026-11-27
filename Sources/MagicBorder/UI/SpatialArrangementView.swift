import AppKit
import MagicBorderKit
import SwiftUI

struct SpatialArrangementView: View {
    let machines: [Machine]
    let twoRow: Bool
    let activeMachineID: UUID?
    let telemetryByID: [UUID: PeerTelemetry]
    var onSwitch: (Machine) -> Void
    var onSendClipboard: () -> Void
    var onReconnect: (Machine) -> Void
    var onDisconnect: (Machine) -> Void

    var body: some View {
        let columns = self.twoRow ? 2 : max(1, self.machines.count)
        let rows = self.machines.chunked(into: max(1, columns))

        VStack(spacing: 16) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(alignment: .center, spacing: 14) {
                    ForEach(Array(rows[rowIndex].enumerated()), id: \.element.id) { colIndex, machine in
                        self.displayNode(for: machine)
                        if colIndex < rows[rowIndex].count - 1 {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                if rowIndex < rows.count - 1 {
                    HStack(spacing: 24) {
                        ForEach(0..<rows[rowIndex].count, id: \.self) { _ in
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func displayNode(for machine: Machine) -> some View {
        let isLocal = machine.state == .local
        let isFocused = (self.activeMachineID == nil && isLocal) || (self.activeMachineID == machine.id)
        let resolution = Self.effectiveResolution(for: machine)
        let boxSize = Self.scaledDisplaySize(for: resolution)
        let telemetry = self.telemetryByID[machine.id]

        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFocused ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isFocused ? Color.accentColor : Color.secondary.opacity(0.35),
                                lineWidth: isFocused ? 2 : 1))

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
            .overlay(alignment: .topTrailing) {
                if let rtt = telemetry?.rttMs {
                    Text("\(rtt) ms")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
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
            }
        }
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            self.onSwitch(machine)
        }
        .contextMenu {
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
        let baseHeight: CGFloat = 104
        return CGSize(width: min(230, max(120, baseHeight * ratio)), height: baseHeight)
    }
}

extension Array {
    fileprivate func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
