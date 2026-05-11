import Foundation
@testable import MagicBorderKit
import XCTest

final class MachineArrangementTests: XCTestCase {
    func testNextUsesAtLeastOneColumnWhenColumnCountIsInvalid() {
        let first = UUID()
        let second = UUID()
        let arrangement = MachineArrangement(slots: [first, second], columns: 0)

        XCTAssertEqual(
            arrangement.next(from: first, direction: .down, wraps: false, oneRow: false),
            second)
    }

    func testWrappedIncompleteGridDoesNotReturnMissingCell() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let arrangement = MachineArrangement(slots: [first, second, third], columns: 2)

        XCTAssertNil(
            arrangement.next(from: third, direction: .right, wraps: true, oneRow: false))
    }

    func testOneRowWrapsHorizontallyOnly() {
        let first = UUID()
        let second = UUID()
        let arrangement = MachineArrangement(slots: [first, second], columns: 2)

        XCTAssertEqual(
            arrangement.next(from: first, direction: .left, wraps: true, oneRow: true),
            second)
        XCTAssertNil(arrangement.next(from: first, direction: .up, wraps: true, oneRow: true))
    }

    func testTwoRowNavigationFindsVerticalNeighbor() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let fourth = UUID()
        let arrangement = MachineArrangement(slots: [first, second, third, fourth], columns: 2)

        XCTAssertEqual(arrangement.next(from: first, direction: .down, wraps: false, oneRow: false), third)
        XCTAssertEqual(arrangement.next(from: fourth, direction: .up, wraps: false, oneRow: false), second)
    }

    func testMoveReordersSourceToDestinationPosition() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var arrangement = MachineArrangement(slots: [first, second, third], columns: 3)

        arrangement.move(from: first, to: third)

        XCTAssertEqual(arrangement.slots, [second, third, first])
    }

    func testMoveIgnoresUnknownIds() {
        let first = UUID()
        let second = UUID()
        var arrangement = MachineArrangement(slots: [first, second], columns: 2)

        arrangement.move(from: UUID(), to: second)

        XCTAssertEqual(arrangement.slots, [first, second])
    }

    func testInsertDoesNotDuplicateExistingMachine() {
        let first = UUID()
        var arrangement = MachineArrangement(slots: [first], columns: 1)

        arrangement.insert(first)

        XCTAssertEqual(arrangement.slots, [first])
    }

    func testRemoveDeletesMachineFromArrangement() {
        let first = UUID()
        let second = UUID()
        var arrangement = MachineArrangement(slots: [first, second], columns: 2)

        arrangement.remove(first)

        XCTAssertEqual(arrangement.slots, [second])
    }
}
