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
        HStack(spacing: 20) {
            ForEach(machines) { machine in
                MachineCard(name: machine.name, isOnline: machine.isOnline)
                    .onDrag {
                        self.draggingMachine = machine
                        return NSItemProvider(object: machine.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: MachineDropDelegate(
                            item: machine, machines: $machines, draggingItem: $draggingMachine))
            }
        }
        .padding()
        .background(Material.ultraThin)
        .cornerRadius(12)
        .animation(.default, value: machines)
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
                    if #available(macOS 14.0, *) {
                        Image(systemName: "desktopcomputer")
                            .font(.largeTitle)
                            .symbolEffect(.bounce, value: isOnline)
                    } else {
                        Image(systemName: "desktopcomputer")
                            .font(.largeTitle)
                    }
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
    @State var demoMachines = [
        Machine(id: UUID(), name: "MacBook Pro", isOnline: true),
        Machine(id: UUID(), name: "Windows PC", isOnline: false),
        Machine(id: UUID(), name: "Linux Server", isOnline: false),
    ]
    MachineMatrixView(machines: $demoMachines)
        .padding()
}
