import Foundation
@testable import MagicBorderKit
import XCTest

final class MachineListResolverTests: XCTestCase {
    func testVisibleMachinesStartWithLocalMachineWhenArrangementIsEmpty() {
        let localID = UUID()
        let remote = Machine(id: UUID(), name: "Windows", state: .connected)

        let machines = MachineListResolver.visibleMachines(
            localMachineID: localID,
            localMachineName: "Mac",
            connectedMachines: [remote],
            arrangement: MachineArrangement())

        XCTAssertEqual(machines.map(\.id), [localID, remote.id])
        XCTAssertEqual(machines.first?.state, .local)
    }

    func testVisibleMachinesFollowArrangementAndAppendMissingConnectedMachines() {
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

        XCTAssertEqual(machines.map(\.id), [firstRemote.id, localID, secondRemote.id])
    }

    func testVisibleMachinesDoNotCrashWhenConnectedListContainsDuplicateID() {
        let localID = UUID()
        let duplicate = Machine(id: UUID(), name: "Windows", state: .connected)

        let machines = MachineListResolver.visibleMachines(
            localMachineID: localID,
            localMachineName: "Mac",
            connectedMachines: [duplicate, duplicate],
            arrangement: MachineArrangement(slots: [duplicate.id], columns: 2))

        XCTAssertEqual(machines.map(\.id), [duplicate.id, localID])
    }

    func testVisibleMachinesPreserveLocalStateWhenConnectedListContainsLocalID() {
        let localID = UUID()
        let remoteCopyOfLocal = Machine(id: localID, name: "Stale Mac", state: .connected)

        let machines = MachineListResolver.visibleMachines(
            localMachineID: localID,
            localMachineName: "Mac",
            connectedMachines: [remoteCopyOfLocal],
            arrangement: MachineArrangement(slots: [localID], columns: 2))

        XCTAssertEqual(machines.map(\.id), [localID])
        XCTAssertEqual(machines.first?.name, "Mac")
        XCTAssertEqual(machines.first?.state, .local)
    }
}
