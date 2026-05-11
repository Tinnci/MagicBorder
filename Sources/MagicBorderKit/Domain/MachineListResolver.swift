import Foundation

public enum MachineListResolver {
    public static func visibleMachines(
        localMachineID: UUID,
        localMachineName: String,
        connectedMachines: [Machine],
        arrangement: MachineArrangement) -> [Machine]
    {
        let localMachine = Machine(
            id: localMachineID,
            name: localMachineName,
            state: .local)
        let allMachines = [localMachine] + connectedMachines
        let machineByID = allMachines.reduce(into: [UUID: Machine]()) { result, machine in
            if result[machine.id] == nil {
                result[machine.id] = machine
            }
        }

        var ordered: [Machine] = []
        for id in arrangement.slots {
            if let machine = machineByID[id] {
                ordered.append(machine)
            }
        }

        for machine in allMachines where !ordered.contains(where: { $0.id == machine.id }) {
            ordered.append(machine)
        }

        return ordered
    }
}
