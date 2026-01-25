import SwiftUI
import UniformTypeIdentifiers



struct MachineMatrixView: View {
    @Binding var machines: [Machine]
    var columns: Int = 2
    @State private var draggingMachine: Machine?

    var body: some View {
        Grid(horizontalSpacing: 20, verticalSpacing: 20) {
            let rows = machines.chunked(into: max(1, columns))
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

    @State private var isHovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                isOnline
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(Material.thick)
            )
            .frame(width: 120, height: 80)
            .overlay {
                // Online Glow
                if isOnline {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        .shadow(color: .blue.opacity(0.5), radius: 10)
                }
            }
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                        .font(.title)
                        .symbolEffect(.bounce, value: isOnline)
                        .foregroundStyle(isOnline ? .white : .secondary)

                    Text(name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(isOnline ? .white : .secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }
            }
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
            .onHover { isHovering = $0 }
            // Dim if offline
            .opacity(isOnline ? 1 : 0.6)
            .saturation(isOnline ? 1 : 0)
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
