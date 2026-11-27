import MagicBorderKit
import SwiftUI
import UniformTypeIdentifiers

struct MachineMatrixView: View {
    @Binding var machines: [Machine]
    var columns: Int = 2
    var activeMachineID: UUID?
    var selectedMachineID: UUID?
    var onSelect: ((Machine) -> Void)?
    var onSwitch: ((Machine) -> Void)?
    var onSendClipboard: (() -> Void)?
    var onReconnect: ((Machine) -> Void)?
    var onDisconnect: ((Machine) -> Void)?
    var onAddMachine: (() -> Void)?

    @State private var draggingMachine: Machine?
    @State private var hoveredDropID: UUID?

    var body: some View {
        let rows = self.machines.chunked(into: max(1, self.columns))
        VStack(spacing: 12) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(Array(rows[rowIndex].enumerated()), id: \.element.id) { colIndex, machine in
                            HStack(spacing: 8) {
                                self.card(for: machine)
                                if colIndex < rows[rowIndex].count - 1 {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        if rows.count == 1, rows[rowIndex].count == 1, let onAddMachine {
                            AddMachineSlotCard(action: onAddMachine)
                                .frame(minWidth: 160, maxWidth: .infinity, minHeight: 92)
                        }
                    }

                    if rowIndex < rows.count - 1 {
                        HStack(spacing: 24) {
                            ForEach(0..<rows[rowIndex].count, id: \.self) { _ in
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(8)
            .animation(.default, value: self.machines)
        }
    }

    @ViewBuilder
    private func card(for machine: Machine) -> some View {
        let isFocused =
            (self.activeMachineID == nil && machine.state == .local)
            || (self.activeMachineID == machine.id)
        let isSelected = self.selectedMachineID == machine.id
        let isDropHighlighted = self.hoveredDropID == machine.id && self.draggingMachine != machine

        MachineCard(
            machine: machine,
            isFocused: isFocused,
            isSelected: isSelected,
            isDropHighlighted: isDropHighlighted
        )
        .frame(minWidth: 160, maxWidth: .infinity, minHeight: 92)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            self.onSwitch?(machine)
        }
        .onTapGesture {
            self.onSelect?(machine)
        }
        .contextMenu {
            Button(
                machine.state == .local
                    ? localizedString("Return Control Here")
                    : localizedString("Switch to Machine")
            ) {
                self.onSwitch?(machine)
            }
            if machine.state != .local {
                Button(localizedString("Send Clipboard Now")) {
                    self.onSendClipboard?()
                }
                Button(localizedString("Restart Connection")) {
                    self.onReconnect?(machine)
                }
                Divider()
                Button(localizedString("Disconnect"), role: .destructive) {
                    self.onDisconnect?(machine)
                }
            }
        }
        .onDrag {
            self.draggingMachine = machine
            return NSItemProvider(object: machine.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: MachineDropDelegate(
                item: machine,
                machines: self.$machines,
                draggingItem: self.$draggingMachine,
                hoveredID: self.$hoveredDropID))
    }
}

extension Array {
    fileprivate func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

struct MachineCard: View {
    let machine: Machine
    var isFocused: Bool = false
    var isSelected: Bool = false
    var isDropHighlighted: Bool = false

    private var iconName: String {
        if self.machine.state == .local {
            return "macbook"
        }
        return self.machine.mwbPeerID != nil ? "pc" : "desktopcomputer"
    }

    private var subtitleText: String {
        if self.machine.state == .local {
            return localizedString("This Mac")
        }
        if self.machine.mwbPeerID != nil {
            return self.machine.isOnline ? localizedString("Windows • Online") : localizedString("Windows • Offline")
        }
        return self.machine.isOnline ? localizedString("Online") : localizedString("Offline")
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 8) {
                HStack {
                    if self.isFocused {
                        Label(localizedString("Controlling"), systemImage: "cursorarrow.rays")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                    Spacer()
                    StatusDot(active: self.machine.isOnline || self.machine.state == .local)
                }

                Image(systemName: self.iconName)
                    .font(.system(size: 30))
                    .foregroundStyle(
                        self.isFocused || self.machine.isOnline || self.machine.state == .local
                            ? Color.accentColor : Color.secondary)

                VStack(spacing: 2) {
                    Text(self.machine.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(self.subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    self.isDropHighlighted || self.isFocused
                        ? Color.accentColor
                        : (self.isSelected ? Color.accentColor.opacity(0.5) : Color.clear),
                    lineWidth: self.isFocused || self.isDropHighlighted ? 2 : 1.5))
    }
}

private struct AddMachineSlotCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.dashed")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                Text(localizedString("Pair a Machine"))
                    .font(.headline)
                Text(localizedString("Click to discover or enter an IP"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(.secondary.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }
}

struct MachineDropDelegate: DropDelegate {
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
            let from = machines.firstIndex(of: draggingItem),
            let to = machines.firstIndex(of: item)
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
