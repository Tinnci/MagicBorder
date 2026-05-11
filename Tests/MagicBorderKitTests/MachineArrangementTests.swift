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
}
