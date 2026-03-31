import Foundation

// MARK: - ArrangementDirection

/// Cardinal direction for grid navigation.
public enum ArrangementDirection: Sendable {
    case left
    case right
    case up
    case down
}

// MARK: - MachineArrangement

/// Aggregate root for the spatial grid layout of machines.
///
/// Owns the ordered sequence of machine UUIDs and all grid-navigation logic
/// that was previously embedded in `MBNetworkManager.nextMachineName(for:from:)`.
/// The UI layer derives `[Machine]` by resolving slots against the connected
/// machine list; it does not store `Machine` objects directly.
public struct MachineArrangement: Codable, Equatable, Sendable {
    // MARK: - Properties

    /// Machine UUIDs in row-major grid order.
    public var slots: [UUID]

    /// Number of columns in the 2D grid.
    public var columns: Int

    // MARK: - Init

    public init(slots: [UUID] = [], columns: Int = 2) {
        self.slots = slots
        self.columns = columns
    }

    // MARK: - Mutation

    /// Reorder `sourceId` to the position of `destinationId`.
    public mutating func move(from sourceId: UUID, to destinationId: UUID) {
        guard let fromIndex = slots.firstIndex(of: sourceId),
              let toIndex = slots.firstIndex(of: destinationId)
        else { return }
        self.slots.remove(at: fromIndex)
        self.slots.insert(sourceId, at: min(toIndex, self.slots.count))
    }

    /// Add a machine to the end of the arrangement if not already present.
    public mutating func insert(_ id: UUID) {
        if !self.slots.contains(id) { self.slots.append(id) }
    }

    /// Remove a machine from the arrangement.
    public mutating func remove(_ id: UUID) {
        self.slots.removeAll { $0 == id }
    }

    // MARK: - Navigation

    /// Returns the UUID of the machine adjacent to `machineId` in the given direction.
    ///
    /// - Parameters:
    ///   - machineId: The current machine's UUID.
    ///   - direction: The cardinal direction to navigate.
    ///   - wraps: When `true`, navigation wraps around edges (circle mode).
    ///   - oneRow: When `true`, treats the arrangement as a single-row list.
    public func next(
        from machineId: UUID,
        direction: ArrangementDirection,
        wraps: Bool,
        oneRow: Bool) -> UUID?
    {
        guard let currentIndex = slots.firstIndex(of: machineId) else { return nil }

        if oneRow {
            switch direction {
            case .left:
                let next = currentIndex - 1
                if next >= 0 { return self.slots[next] }
                return wraps ? self.slots.last : nil
            case .right:
                let next = currentIndex + 1
                if next < self.slots.count { return self.slots[next] }
                return wraps ? self.slots.first : nil
            case .up, .down:
                return nil
            }
        }

        let row = currentIndex / self.columns
        let col = currentIndex % self.columns
        let rowCount = Int((slots.count + self.columns - 1) / self.columns)

        var newRow = row
        var newCol = col

        switch direction {
        case .left: newCol -= 1
        case .right: newCol += 1
        case .up: newRow -= 1
        case .down: newRow += 1
        }

        if wraps {
            if newCol < 0 { newCol = self.columns - 1 }
            if newCol >= self.columns { newCol = 0 }
            if newRow < 0 { newRow = rowCount - 1 }
            if newRow >= rowCount { newRow = 0 }
        }

        let newIndex = newRow * self.columns + newCol
        guard newIndex >= 0, newIndex < self.slots.count else { return nil }
        return self.slots[newIndex]
    }
}
