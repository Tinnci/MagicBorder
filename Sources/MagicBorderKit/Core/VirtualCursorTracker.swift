public import CoreGraphics

/// Pure value-type state machine tracking virtual cursor position while in remote mode.
public struct MBVirtualCursorTracker: Equatable, Sendable {
    public private(set) var position: CGPoint?

    public init(position: CGPoint? = nil) {
        self.position = position
    }

    public mutating func advance(
        startLocation: CGPoint,
        deltaX: Int64,
        deltaY: Int64,
        screenFrame: CGRect?
    ) -> CGPoint {
        var next = self.position ?? startLocation
        next.x += CGFloat(deltaX)
        next.y += CGFloat(deltaY)

        if let frame = screenFrame {
            next.x = max(frame.minX, min(next.x, frame.maxX))
            next.y = max(frame.minY, min(next.y, frame.maxY))
        }

        self.position = next
        return next
    }

    public mutating func reset() {
        self.position = nil
    }
}
