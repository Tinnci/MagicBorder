import SwiftUI
import UniformTypeIdentifiers

struct Machine: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var isOnline: Bool
}

struct MachineMatrixView: View {
    @Binding var machines: [Machine]
    @State private var draggingMachine: Machine?

    var body: some View {
        Grid(horizontalSpacing: 20, verticalSpacing: 20) {
            // Display machines in a grid (e.g., 2 columns)
            // For simplicity in this specialized view, we use chunks if more than 2
            let rows = machines.chunked(into: 2)
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                GridRow {
                    ForEach(rows[rowIndex]) { machine in
                        MachineCard(name: machine.name, isOnline: machine.isOnline)
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
        .padding()
        .background(Material.ultraThin)
        .cornerRadius(12)
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
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(isOnline ? Color.blue.gradient : Color.gray.gradient)
            .frame(width: 120, height: 80)
            .overlay {
                VStack {
                    Image(systemName: "desktopcomputer")
                        .font(.largeTitle)
                        .symbolEffect(.bounce, value: isOnline)

                    Text(name)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
            }
            .shadow(radius: isOnline ? 5 : 0)
            .scaleEffect(isOnline ? 1.05 : 1.0)
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
