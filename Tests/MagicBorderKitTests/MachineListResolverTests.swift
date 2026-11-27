import Foundation
import Testing

@testable import MagicBorderKit

@Suite("MachineListResolver")
struct MachineListResolverTests {
    @Test func visibleMachinesStartWithLocalMachineWhenArrangementIsEmpty() {
        let localID = UUID()
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)

        let machines = MachineListResolver.visibleMachines(
            localMachineID: localID,
            localMachineName: "Mac",
            connectedMachines: [remote],
            arrangement: MachineArrangement())

        #expect(machines.map(\.id) == [localID, remote.id])
        #expect(machines.first?.state == .local)
    }

    @Test func visibleMachinesFollowArrangementAndAppendMissingConnectedMachines() {
        let localID = UUID()
        let firstRemote = Machine(id: UUID(), name: "Windows", state: .connected)
        let secondRemote = Machine(id: UUID(), name: "Linux", state: .connected)
        let staleID = UUID()
        let arrangement = MachineArrangement(
            slots: [firstRemote.id, staleID, localID],
            columns: 2)

        let machines = MachineListResolver.visibleMachines(
            localMachineID: localID,
            localMachineName: "Mac",
            connectedMachines: [secondRemote, firstRemote],
            arrangement: arrangement)

        #expect(machines.map(\.id) == [firstRemote.id, localID, secondRemote.id])
    }

    @Test func visibleMachinesHandleDuplicateIDsInConnectedList() {
        let localID = UUID()
        let duplicate = Machine(id: UUID(), name: "Windows", state: .connected)

        let machines = MachineListResolver.visibleMachines(
            localMachineID: localID,
            localMachineName: "Mac",
            connectedMachines: [duplicate, duplicate],
            arrangement: MachineArrangement(slots: [duplicate.id], columns: 2))

        #expect(machines.map(\.id) == [duplicate.id, localID])
    }

    @Test func visibleMachinesPreserveLocalStateWhenConnectedListContainsLocalID() {
        let localID = UUID()
        let remoteCopyOfLocal = Machine(id: localID, name: "Stale Mac", state: .connected)

        let machines = MachineListResolver.visibleMachines(
            localMachineID: localID,
            localMachineName: "Mac",
            connectedMachines: [remoteCopyOfLocal],
            arrangement: MachineArrangement(slots: [localID], columns: 2))

        #expect(machines.map(\.id) == [localID])
        #expect(machines.first?.name == "Mac")
        #expect(machines.first?.state == .local)
    }
}
