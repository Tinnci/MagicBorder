import SwiftUI
import UniformTypeIdentifiers

struct MachineMatrixView: View {
    @Binding var machines: [Machine]
    var columns: Int = 2
    @State private var draggingMachine: Machine?

    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            let rows = machines.chunked(into: max(1, columns))
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                GridRow {
                    ForEach(rows[rowIndex]) { machine in
                        MachineCard(name: machine.name, isOnline: machine.isOnline)
                            .frame(minWidth: 140, maxWidth: .infinity, minHeight: 72)
                            .onDrag {
                                self.draggingMachine = machine
                                return NSItemProvider(object: machine.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: MachineDropDelegate(
                                    item: machine, machines: $machines,
                                    draggingItem: $draggingMachine))
                    }
                }
            }
        }
        .padding(8)
        .animation(.default, value: machines)
    }
}

// Helper for grid chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

struct MachineCard: View {
    let name: String
    let isOnline: Bool

    var body: some View {
        GroupBox {
            VStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 32))
                    .foregroundStyle(isOnline ? Color.accentColor : Color.secondary)

                VStack(spacing: 4) {
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 4) {
                        StatusDot(active: isOnline)
                        Text(isOnline ? "Online" : "Offline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .contentShape(Rectangle())
    }
}

struct MachineDropDelegate: DropDelegate {
    let item: Machine
    @Binding var machines: [Machine]
    @Binding var draggingItem: Machine?

    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem else { return }

        if item != draggingItem {
            if let from = machines.firstIndex(of: draggingItem),
                let to = machines.firstIndex(of: item)
            {
                withAnimation {
                    machines.move(
                        fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        self.draggingItem = nil
        return true
    }
}

// Preview
#Preview {
    @Previewable @State var demoMachines = [
        Machine(id: UUID(), name: "MacBook Pro", isOnline: true),
        Machine(id: UUID(), name: "Windows PC", isOnline: false),
        Machine(id: UUID(), name: "Linux Server", isOnline: false),
    ]
    MachineMatrixView(machines: $demoMachines)
        .padding()
}
