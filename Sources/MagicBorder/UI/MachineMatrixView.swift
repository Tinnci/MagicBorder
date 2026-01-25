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
        Button(action: {}) {
            VStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 24))
                    .foregroundStyle(isOnline ? Color.accentColor : Color.secondary)

                VStack(spacing: 2) {
                    Text(name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        StatusDot(active: isOnline)
                        Text(isOnline ? "Online" : "Offline")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding()
        }
        .buttonStyle(MachineCardButtonStyle())
    }
}

struct MachineCardButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.separator.opacity(isHovering || configuration.isPressed ? 1.0 : 0.2), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.snappy(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovering = $0 }
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
