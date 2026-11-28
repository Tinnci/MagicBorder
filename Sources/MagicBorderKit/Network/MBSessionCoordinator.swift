import CoreGraphics
public import Foundation
private import OSLog
public import Observation

/// Coordinates active-machine switching, edge-switching guards, and return-to-local transitions.
@MainActor
@Observable
public final class MBSessionCoordinator: Observation.Observable {
    public enum SwitchState: String, Sendable {
        case idle
        case switching
        case active
    }

    public enum SwitchReason: Sendable {
        case manual
        case edge
    }

    public struct Dependencies {
        public let connectedMachines: () -> [Machine]
        public let arrangement: () -> MachineArrangement
        public let settings: () -> MBCompatibilitySettings
        public let updateRemoteTarget: (UUID?) -> Void
        public let emitToast: (MBToastEvent) -> Void
        public let appendLog: (String) -> Void
        /// Requests remote activation; returns `true` if handled asynchronously (MWB) or `false` if immediate (Modern).
        public let activateRemoteMachine: (Machine?) -> Bool
        public let centerRemoteCursor: () -> Void
        public let isFrontmostAppFullscreen: () -> Bool

        public init(
            connectedMachines: @escaping () -> [Machine],
            arrangement: @escaping () -> MachineArrangement,
            settings: @escaping () -> MBCompatibilitySettings,
            updateRemoteTarget: @escaping (UUID?) -> Void,
            emitToast: @escaping (MBToastEvent) -> Void,
            appendLog: @escaping (String) -> Void,
            activateRemoteMachine: @escaping (Machine?) -> Bool,
            centerRemoteCursor: @escaping () -> Void,
            isFrontmostAppFullscreen: @escaping () -> Bool = { false }
        ) {
            self.connectedMachines = connectedMachines
            self.arrangement = arrangement
            self.settings = settings
            self.updateRemoteTarget = updateRemoteTarget
            self.emitToast = emitToast
            self.appendLog = appendLog
            self.activateRemoteMachine = activateRemoteMachine
            self.centerRemoteCursor = centerRemoteCursor
            self.isFrontmostAppFullscreen = isFrontmostAppFullscreen
        }
    }

    public var switchState: SwitchState = .idle
    public var activeMachineId: UUID?
    public var activeMachineName: String
    public var lastSwitchTimestamp: Date?
    public var isCursorLocked: Bool = false
    public var isInputPaused: Bool = false

    private let localMachineID: UUID
    private let localMachineName: String
    private let deps: Dependencies
    private let screenGeometry: any ScreenGeometryProviding
    private let clock: any ClockProviding
    private let cursorController: any CursorControlling

    private var lastEdgeSwitchTime: TimeInterval = 0
    private var edgeSwitchLockedUntil: TimeInterval = 0
    private var edgeSwitchPendingRelease = false
    private var edgeDwellDirection: EdgeDirection?
    private var edgeDwellStartTime: TimeInterval?
    private var lastNoTargetDirection: EdgeDirection?
    private var lastNoTargetLogTime: TimeInterval = 0

    public init(
        localMachineID: UUID,
        localMachineName: String,
        dependencies: Dependencies,
        screenGeometry: any ScreenGeometryProviding = SystemScreenGeometryProvider(),
        clock: any ClockProviding = SystemClock(),
        cursorController: any CursorControlling = SystemCursorController()
    ) {
        self.localMachineID = localMachineID
        self.localMachineName = localMachineName
        self.deps = dependencies
        self.screenGeometry = screenGeometry
        self.clock = clock
        self.cursorController = cursorController
        self.activeMachineName = localMachineName
    }

    public func setActiveMachine(_ id: UUID?, nameHint: String? = nil, notify: Bool = true) {
        let previousID = self.activeMachineId
        self.activeMachineId = id
        self.deps.updateRemoteTarget(id)

        if let id {
            let machineName =
                self.deps.connectedMachines().first(where: { $0.id == id })?.name
                ?? nameHint
                ?? self.localMachineName
            self.activeMachineName = machineName
            self.switchState = .active
            self.lastSwitchTimestamp = Date()
            if notify, previousID != id {
                self.deps.emitToast(.switchedToMachine(machineName))
            }
            return
        }

        self.activeMachineName = self.localMachineName
        self.switchState = .idle
        self.lastSwitchTimestamp = Date()
        if notify, previousID != nil {
            self.deps.emitToast(.returnedToLocal)
        }
    }

    public func handleTransportActiveMachineChanged(id: UUID?, name: String?) {
        self.setActiveMachine(id, nameHint: name)
        if id == nil {
            self.cursorController.unhide()
        }
    }

    public func requestSwitch(to machineId: UUID, reason: SwitchReason = .manual) {
        guard let machine = self.deps.connectedMachines().first(where: { $0.id == machineId }) else {
            return
        }

        guard self.deps.activateRemoteMachine(machine) else {
            self.setActiveMachine(machineId)
            return
        }

        self.switchState = .switching
        self.deps.emitToast(.switchingToMachine(machine.name))

        if reason == .manual {
            self.setEdgeSwitchGuard()
            self.centerRemoteCursorIfPossible()
        }
    }

    public func requestSwitch(toMachineNamed name: String, reason: SwitchReason = .manual) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized == self.localMachineName.uppercased() {
            self.forceReturnToLocal(reason: "manual-name-switch")
            return
        }

        guard
            let target = self.deps.connectedMachines().first(where: {
                $0.name.uppercased() == normalized
            })
        else { return }

        self.requestSwitch(to: target.id, reason: reason)
    }

    public func forceReturnToLocal(reason: String) {
        guard self.activeMachineId != nil else { return }

        _ = self.deps.activateRemoteMachine(nil)
        self.setActiveMachine(nil)
        self.cursorController.unhide()
        self.deps.appendLog("Force return to local (\(reason))")
    }

    public func toggleCursorLock() {
        self.isCursorLocked.toggle()
        self.resetEdgeDwell()
        self.deps.emitToast(self.isCursorLocked ? .cursorLocked : .cursorUnlocked)
    }

    public func handleLocalMouseEvent(snapshot: EventSnapshot) {
        let settings = self.deps.settings()
        guard settings.switchByMouse,
            self.activeMachineId == nil,
            !self.deps.connectedMachines().isEmpty
        else {
            self.resetEdgeDwell()
            return
        }
        guard !self.isCursorLocked,
            !self.isInputPaused,
            !(settings.lockCursorInFullscreenApps && self.deps.isFrontmostAppFullscreen())
        else {
            self.resetEdgeDwell()
            return
        }
        guard settings.edgeCrossingModifier.matches(snapshot.flags) else {
            self.resetEdgeDwell()
            return
        }
        guard let edgeContext = self.evaluateEdgeGuards(snapshot: snapshot, settings: settings) else {
            self.resetEdgeDwell()
            return
        }

        let now = self.clock.now()
        guard now >= self.edgeSwitchLockedUntil else { return }
        guard let dir = edgeContext.direction else {
            self.resetEdgeDwell()
            return
        }

        if settings.edgeDwellSeconds > 0 {
            if self.edgeDwellDirection != dir {
                self.edgeDwellDirection = dir
                self.edgeDwellStartTime = now
                return
            }
            if now - (self.edgeDwellStartTime ?? now) < settings.edgeDwellSeconds {
                return
            }
        }

        let effectiveArrangement = self.effectiveArrangement(oneRow: settings.matrixOneRow)
        guard
            let targetId = effectiveArrangement.next(
                from: self.localMachineID,
                direction: dir.arrangementDirection,
                wraps: settings.matrixCircle,
                oneRow: settings.matrixOneRow)
        else {
            if self.lastNoTargetDirection != dir || now - self.lastNoTargetLogTime > 1.0 {
                self.lastNoTargetDirection = dir
                self.lastNoTargetLogTime = now
                MBLogger.network.debug("Edge check: no target for direction")
            }
            return
        }

        guard now - self.lastEdgeSwitchTime >= 0.1 else { return }
        self.resetEdgeDwell()
        self.triggerEdgeSwitch(to: targetId, direction: dir, at: now)
    }

    private func resetEdgeDwell() {
        self.edgeDwellDirection = nil
        self.edgeDwellStartTime = nil
    }

    public func handleRemoteMouseEvent(snapshot: EventSnapshot) {
        let settings = self.deps.settings()
        guard settings.switchByMouse, let activeMachineId = self.activeMachineId else { return }
        guard let edgeContext = self.evaluateEdgeGuards(snapshot: snapshot, settings: settings) else {
            return
        }

        let now = self.clock.now()
        guard now >= self.edgeSwitchLockedUntil, now - self.lastEdgeSwitchTime >= 0.1 else {
            return
        }

        // Only lock/arm the edge guard once the cursor actually reaches a screen edge.
        guard let dir = edgeContext.direction else { return }

        let targetId =
            self.effectiveArrangement(oneRow: settings.matrixOneRow).next(
                from: activeMachineId,
                direction: dir.arrangementDirection,
                wraps: settings.matrixCircle,
                oneRow: settings.matrixOneRow) ?? self.localMachineID

        self.triggerEdgeSwitch(to: targetId, direction: dir, at: now)
    }

    private func evaluateEdgeGuards(
        snapshot: EventSnapshot,
        settings: MBCompatibilitySettings
    ) -> EdgeContext? {
        guard let mainScreenFrame = self.screenGeometry.mainScreenFrame else { return nil }
        guard
            let edgeContext = self.makeEdgeContext(
                snapshot: snapshot,
                mainScreenFrame: mainScreenFrame,
                settings: settings)
        else { return nil }

        if self.edgeSwitchPendingRelease {
            let margin = CGFloat(settings.edgeSwitchSafeMargin)
            if self.isAwayFromEdges(location: edgeContext.edgeLocation, bounds: edgeContext.bounds, margin: margin) {
                self.edgeSwitchPendingRelease = false
            } else {
                return nil
            }
        }

        return edgeContext
    }

    private func triggerEdgeSwitch(to targetId: UUID, direction: EdgeDirection, at now: TimeInterval) {
        self.lastEdgeSwitchTime = now
        self.setEdgeSwitchGuard(at: now)
        MBLogger.network.info("Edge switch triggered: \(String(describing: direction)) -> \(targetId)")

        if targetId == self.localMachineID {
            self.forceReturnToLocal(reason: "edge")
        } else {
            self.requestSwitch(to: targetId, reason: .edge)
        }
    }

    private func centerRemoteCursorIfPossible() {
        let settings = self.deps.settings()
        guard !settings.moveMouseRelatively, settings.centerCursorOnManualSwitch else { return }
        self.deps.centerRemoteCursor()
    }

    private func setEdgeSwitchGuard(at now: TimeInterval? = nil) {
        let timestamp = now ?? self.clock.now()
        let lockSeconds = max(0.05, self.deps.settings().edgeSwitchLockSeconds)
        self.edgeSwitchLockedUntil = timestamp + lockSeconds
        self.edgeSwitchPendingRelease = true
    }

    private func isAwayFromEdges(location: CGPoint, bounds: CGRect, margin: CGFloat) -> Bool {
        location.x > bounds.minX + margin
            && location.x < bounds.maxX - margin
            && location.y > bounds.minY + margin
            && location.y < bounds.maxY - margin
    }

    private func effectiveArrangement(oneRow: Bool) -> MachineArrangement {
        let connectedMachineIDs = self.deps.connectedMachines().map(\.id)
        let validIDs = Set([self.localMachineID] + connectedMachineIDs)

        var slots = self.deps.arrangement().slots.filter { validIDs.contains($0) }
        for id in [self.localMachineID] + connectedMachineIDs where !slots.contains(id) {
            slots.append(id)
        }

        let columnCount = oneRow ? max(1, slots.count) : max(1, self.deps.arrangement().columns)
        return MachineArrangement(slots: slots, columns: columnCount)
    }

    private func makeEdgeContext(
        snapshot: EventSnapshot,
        mainScreenFrame: CGRect,
        settings: MBCompatibilitySettings
    ) -> EdgeContext? {
        let threshold: CGFloat = 3
        let location = snapshot.location
        let cocoaY = mainScreenFrame.maxY - (location.y - mainScreenFrame.origin.y)
        let edgeLocation = CGPoint(x: location.x, y: cocoaY)
        let allFrames = self.screenGeometry.allScreenFrames
        let bounds = allFrames.first(where: { $0.contains(edgeLocation) }) ?? mainScreenFrame

        let nearLeft =
            edgeLocation.x <= bounds.minX + threshold
            && !Self.hasNeighbor(at: CGPoint(x: bounds.minX - 6, y: edgeLocation.y), in: allFrames, excluding: bounds)
        let nearRight =
            edgeLocation.x >= bounds.maxX - threshold
            && !Self.hasNeighbor(at: CGPoint(x: bounds.maxX + 6, y: edgeLocation.y), in: allFrames, excluding: bounds)
        let nearTop =
            edgeLocation.y >= bounds.maxY - threshold
            && !Self.hasNeighbor(at: CGPoint(x: edgeLocation.x, y: bounds.maxY + 6), in: allFrames, excluding: bounds)
        let nearBottom =
            edgeLocation.y <= bounds.minY + threshold
            && !Self.hasNeighbor(at: CGPoint(x: edgeLocation.x, y: bounds.minY - 6), in: allFrames, excluding: bounds)

        if settings.blockCorners, (nearLeft || nearRight) && (nearBottom || nearTop) {
            return nil
        }

        let direction: EdgeDirection? =
            if nearLeft {
                .left
            } else if nearRight {
                .right
            } else if nearTop {
                .up
            } else if nearBottom {
                .down
            } else {
                nil
            }

        return EdgeContext(direction: direction, edgeLocation: edgeLocation, bounds: bounds)
    }

    private static func hasNeighbor(at probe: CGPoint, in frames: [CGRect], excluding current: CGRect) -> Bool {
        frames.contains { frame in
            frame != current && frame.contains(probe)
        }
    }
}

extension MBSessionCoordinator {
    fileprivate struct EdgeContext {
        let direction: EdgeDirection?
        let edgeLocation: CGPoint
        let bounds: CGRect
    }

    fileprivate enum EdgeDirection {
        case left
        case right
        case up
        case down

        var arrangementDirection: ArrangementDirection {
            switch self {
            case .left: .left
            case .right: .right
            case .up: .up
            case .down: .down
            }
        }
    }
}
