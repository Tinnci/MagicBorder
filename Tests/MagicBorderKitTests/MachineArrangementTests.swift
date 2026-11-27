import Foundation
import Testing

@testable import MagicBorderKit

@Suite("MachineArrangement")
struct MachineArrangementTests {
    @Test func nextUsesAtLeastOneColumnWhenColumnCountIsInvalid() {
        let first = UUID()
        let second = UUID()
        let arrangement = MachineArrangement(slots: [first, second], columns: 0)

        #expect(arrangement.next(from: first, direction: .down, wraps: false, oneRow: false) == second)
    }

    @Test func wrappedIncompleteGridDoesNotReturnMissingCell() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let arrangement = MachineArrangement(slots: [first, second, third], columns: 2)

        #expect(arrangement.next(from: third, direction: .right, wraps: true, oneRow: false) == nil)
    }

    @Test func oneRowWrapsHorizontallyOnly() {
        let first = UUID()
        let second = UUID()
        let arrangement = MachineArrangement(slots: [first, second], columns: 2)

        #expect(arrangement.next(from: first, direction: .left, wraps: true, oneRow: true) == second)
        #expect(arrangement.next(from: first, direction: .up, wraps: true, oneRow: true) == nil)
    }

    @Test func twoRowNavigationFindsVerticalNeighbor() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let fourth = UUID()
        let arrangement = MachineArrangement(slots: [first, second, third, fourth], columns: 2)

        #expect(arrangement.next(from: first, direction: .down, wraps: false, oneRow: false) == third)
        #expect(arrangement.next(from: fourth, direction: .up, wraps: false, oneRow: false) == second)
    }

    @Test func moveReordersSourceToDestinationPosition() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var arrangement = MachineArrangement(slots: [first, second, third], columns: 3)

        arrangement.move(from: first, to: third)

        #expect(arrangement.slots == [second, third, first])
    }

    @Test func moveIgnoresUnknownIDs() {
        let first = UUID()
        let second = UUID()
        var arrangement = MachineArrangement(slots: [first, second], columns: 2)

        arrangement.move(from: UUID(), to: second)

        #expect(arrangement.slots == [first, second])
    }

    @Test func insertDoesNotDuplicateExistingMachine() {
        let first = UUID()
        var arrangement = MachineArrangement(slots: [first], columns: 1)

        arrangement.insert(first)

        #expect(arrangement.slots == [first])
    }

    @Test func removeDeletesMachineFromArrangement() {
        let first = UUID()
        let second = UUID()
        var arrangement = MachineArrangement(slots: [first, second], columns: 2)

        arrangement.remove(first)

        #expect(arrangement.slots == [second])
    }
}
