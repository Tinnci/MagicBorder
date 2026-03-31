import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class MBSessionCoordinator: Observation.Observable {
    public enum SwitchState: String {
        case idle
        case switching
        case active
    }

    public enum SwitchReason {
        case manual
        case edge
    }

    public var switchState: SwitchState = .idle
    public var activeMachineId: UUID?
    public var activeMachineName: String
    public var lastSwitchTimestamp: Date?

    private let localMachineID: UUID
    private let localMachineName: String
    private let connectedMachinesProvider: () -> [Machine]
    private let arrangementProvider: () -> MachineArrangement
    private let settingsProvider: () -> MBCompatibilitySettings
    private let protocolModeProvider: () -> MBProtocolMode
    private let updateRemoteTarget: (UUID?) -> Void
    private let showToast: (String, String) -> Void
    private let appendLog: (String) -> Void
    private let activateCompatibilityMachine: (Machine?) -> Void
    private let centerRemoteCursor: () -> Void
    private let unhideCursor: () -> Void

    private var lastEdgeSwitchTime: TimeInterval = 0
    private var edgeSwitchLockedUntil: TimeInterval = 0
    private var edgeSwitchPendingRelease = false
    private var lastNoTargetDirection: EdgeDirection?
    private var lastNoTargetLogTime: TimeInterval = 0

    public init(
        localMachineID: UUID,
        localMachineName: String,
        connectedMachinesProvider: @escaping () -> [Machine],
        arrangementProvider: @escaping () -> MachineArrangement,
        settingsProvider: @escaping () -> MBCompatibilitySettings,
        protocolModeProvider: @escaping () -> MBProtocolMode,
        updateRemoteTarget: @escaping (UUID?) -> Void,
        showToast: @escaping (String, String) -> Void,
        appendLog: @escaping (String) -> Void,
        activateCompatibilityMachine: @escaping (Machine?) -> Void,
        centerRemoteCursor: @escaping () -> Void,
        unhideCursor: @escaping () -> Void = { NSCursor.unhide() })
    {
        self.localMachineID = localMachineID
        self.localMachineName = localMachineName
        self.connectedMachinesProvider = connectedMachinesProvider
        self.arrangementProvider = arrangementProvider
        self.settingsProvider = settingsProvider
        self.protocolModeProvider = protocolModeProvider
        self.updateRemoteTarget = updateRemoteTarget
        self.showToast = showToast
        self.appendLog = appendLog
        self.activateCompatibilityMachine = activateCompatibilityMachine
        self.centerRemoteCursor = centerRemoteCursor
        self.unhideCursor = unhideCursor
        self.activeMachineName = localMachineName
    }

    public func setActiveMachine(_ id: UUID?, nameHint: String? = nil, notify: Bool = true) {
        self.activeMachineId = id
        self.updateRemoteTarget(id)

        if let id {
            let machineName = self.connectedMachinesProvider().first(where: { $0.id == id })?.name
                ?? nameHint
                ?? self.localMachineName
            self.activeMachineName = machineName
            self.switchState = .active
            self.lastSwitchTimestamp = Date()
            if notify {
                self.showToast("已切换到 \(machineName)", "arrow.right")
            }
            return
        }

        self.activeMachineName = self.localMachineName
        self.switchState = .idle
        self.lastSwitchTimestamp = Date()
        if notify {
            self.showToast("已切回本机", "arrow.left")
        }
    }

    public func handleTransportActiveMachineChanged(id: UUID?, name: String?) {
        self.setActiveMachine(id, nameHint: name)
        if id == nil {
            self.unhideCursor()
        }
    }

    public func requestSwitch(to machineId: UUID, reason: SwitchReason = .manual) {
        guard let machine = self.connectedMachinesProvider().first(where: { $0.id == machineId }) else {
            return
        }

        if self.protocolModeProvider() == .modern {
            self.setActiveMachine(machineId)
            return
        }

        self.switchState = .switching
        self.showToast("正在切换到 \(machine.name)", "arrow.triangle.2.circlepath")
        self.activateCompatibilityMachine(machine)

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

        guard let target = self.connectedMachinesProvider().first(where: {
            $0.name.uppercased() == normalized
        }) else {
            return
        }

        self.requestSwitch(to: target.id, reason: reason)
    }

    public func forceReturnToLocal(reason: String) {
        guard self.activeMachineId != nil else { return }

        if self.protocolModeProvider() != .modern {
            self.activateCompatibilityMachine(nil)
        }

        self.setActiveMachine(nil)
        self.unhideCursor()
        self.appendLog("Force return to local (\(reason))")
    }

    public func handleLocalMouseEvent(snapshot: EventSnapshot) {
        let settings = self.settingsProvider()
        guard settings.switchByMouse else {
            MBLogger.network.debug("Edge check skipped: switchByMouse=false")
            return
        }
        guard self.activeMachineId == nil else {
            MBLogger.network.debug("Edge check skipped: activeMachineId != nil")
            return
        }
        guard let mainScreen = NSScreen.main ?? NSScreen.screens.first else {
            MBLogger.network.debug("Edge check skipped: no screen")
            return
        }

        let edgeContext = self.makeEdgeContext(snapshot: snapshot, mainScreen: mainScreen, settings: settings)
        guard let edgeContext else { return }

        if self.edgeSwitchPendingRelease {
            if self.isAwayFromEdges(
                location: edgeContext.edgeLocation,
                bounds: edgeContext.bounds,
                margin: CGFloat(settings.edgeSwitchSafeMargin))
            {
                self.edgeSwitchPendingRelease = false
            } else {
                MBLogger.network.debug("Edge check skipped: pending release")
                return
            }
        }

        let now = CFAbsoluteTimeGetCurrent()
        if now < self.edgeSwitchLockedUntil {
            MBLogger.network.debug("Edge check skipped: locked")
            return
        }

        guard let dir = edgeContext.direction else {
            MBLogger.network.debug("Edge check: not near edge")
            return
        }

        let effectiveArrangement = self.effectiveArrangement(oneRow: settings.matrixOneRow)
        guard let targetId = effectiveArrangement.next(
            from: self.localMachineID,
            direction: self.arrangementDirection(for: dir),
            wraps: settings.matrixCircle,
            oneRow: settings.matrixOneRow)
        else {
            let shouldLog = self.lastNoTargetDirection != dir || now - self.lastNoTargetLogTime > 1.0
            if shouldLog {
                self.lastNoTargetDirection = dir
                self.lastNoTargetLogTime = now
                MBLogger.network.debug("Edge check: no target for direction")
            }
            return
        }

        if now - self.lastEdgeSwitchTime < 0.1 {
            MBLogger.network.debug("Edge check skipped: throttled")
            return
        }

        self.lastEdgeSwitchTime = now
        self.setEdgeSwitchGuard()

        MBLogger.network.info("Edge switch triggered: \(String(describing: dir)) towards \(targetId)")
        if targetId == self.localMachineID {
            self.forceReturnToLocal(reason: "edge")
        } else {
            self.requestSwitch(to: targetId, reason: .edge)
        }
    }

    public func handleRemoteMouseEvent(snapshot: EventSnapshot) {
        let settings = self.settingsProvider()
        guard settings.switchByMouse else { return }
        guard let activeMachineId = self.activeMachineId else { return }
        guard let mainScreen = NSScreen.main ?? NSScreen.screens.first else { return }

        let edgeContext = self.makeEdgeContext(snapshot: snapshot, mainScreen: mainScreen, settings: settings)
        guard let edgeContext else { return }

        if self.edgeSwitchPendingRelease {
            if self.isAwayFromEdges(
                location: edgeContext.edgeLocation,
                bounds: edgeContext.bounds,
                margin: CGFloat(settings.edgeSwitchSafeMargin))
            {
                self.edgeSwitchPendingRelease = false
            } else {
                return
            }
        }

        let now = CFAbsoluteTimeGetCurrent()
        if now < self.edgeSwitchLockedUntil || now - self.lastEdgeSwitchTime < 0.1 {
            return
        }
        self.lastEdgeSwitchTime = now
        self.setEdgeSwitchGuard()

        if let dir = edgeContext.direction,
           let targetId = self.effectiveArrangement(oneRow: settings.matrixOneRow).next(
               from: activeMachineId,
               direction: self.arrangementDirection(for: dir),
               wraps: settings.matrixCircle,
               oneRow: settings.matrixOneRow)
        {
            MBLogger.network.info("Remote edge switch: \(String(describing: dir)) → \(targetId)")
            if targetId == self.localMachineID {
                self.forceReturnToLocal(reason: "edge")
            } else {
                self.requestSwitch(to: targetId, reason: .edge)
            }
            return
        }

        if edgeContext.direction != nil {
            self.forceReturnToLocal(reason: "edge")
        }
    }

    private func centerRemoteCursorIfPossible() {
        let settings = self.settingsProvider()
        guard self.protocolModeProvider() != .modern else { return }
        guard !settings.moveMouseRelatively else { return }
        guard settings.centerCursorOnManualSwitch else { return }
        self.centerRemoteCursor()
    }

    private func setEdgeSwitchGuard() {
        let now = CFAbsoluteTimeGetCurrent()
        let lockSeconds = max(0.05, self.settingsProvider().edgeSwitchLockSeconds)
        self.edgeSwitchLockedUntil = now + lockSeconds
        self.edgeSwitchPendingRelease = true
    }

    private func isAwayFromEdges(location: CGPoint, bounds: CGRect, margin: CGFloat) -> Bool {
        let awayLeft = location.x > bounds.minX + margin
        let awayRight = location.x < bounds.maxX - margin
        let awayBottom = location.y > bounds.minY + margin
        let awayTop = location.y < bounds.maxY - margin
        return awayLeft && awayRight && awayBottom && awayTop
    }

    private func effectiveArrangement(oneRow: Bool) -> MachineArrangement {
        let connectedMachineIDs = self.connectedMachinesProvider().map(\.id)
        let validIDs = Set([self.localMachineID] + connectedMachineIDs)

        var slots = self.arrangementProvider().slots.filter { validIDs.contains($0) }
        for id in [self.localMachineID] + connectedMachineIDs where !slots.contains(id) {
            slots.append(id)
        }

        let columnCount = oneRow ? max(1, slots.count) : max(1, self.arrangementProvider().columns)
        return MachineArrangement(slots: slots, columns: columnCount)
    }

    private func arrangementDirection(for direction: EdgeDirection) -> ArrangementDirection {
        switch direction {
        case .left:
            .left
        case .right:
            .right
        case .up:
            .up
        case .down:
            .down
        }
    }

    private func makeEdgeContext(
        snapshot: EventSnapshot,
        mainScreen: NSScreen,
        settings: MBCompatibilitySettings)
        -> EdgeContext?
    {
        let threshold: CGFloat = 3
        let location = snapshot.location
        let cocoaY = mainScreen.frame.maxY - (location.y - mainScreen.frame.origin.y)
        let edgeLocation = CGPoint(x: location.x, y: cocoaY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(edgeLocation) }) ?? mainScreen
        let bounds = screen.frame

        let nearLeft = edgeLocation.x <= bounds.minX + threshold
        let nearRight = edgeLocation.x >= bounds.maxX - threshold
        let nearTop = edgeLocation.y >= bounds.maxY - threshold
        let nearBottom = edgeLocation.y <= bounds.minY + threshold

        if settings.blockCorners {
            let nearCorner = (nearLeft || nearRight) && (nearBottom || nearTop)
            if nearCorner { return nil }
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
    }
}
