import AppKit

enum MBMenuBarStatus: Equatable, Sendable {
    case permissionNeeded
    case paused
    case locked
    case controllingRemote
    case connected
    case idle
}

@MainActor
enum MBMenuBarIconRenderer {
    static func image(for status: MBMenuBarStatus) -> NSImage {
        switch status {
        case .permissionNeeded:
            return self.symbolImage(named: "exclamationmark.triangle") ?? self.dualDisplayTemplate(status: .idle)
        case .paused:
            return self.symbolImage(named: "pause.circle") ?? self.dualDisplayTemplate(status: .idle)
        case .locked:
            return self.symbolImage(named: "lock.display") ?? self.dualDisplayTemplate(status: .connected)
        case .idle, .connected, .controllingRemote:
            return self.dualDisplayTemplate(status: status)
        }
    }

    private static func symbolImage(named name: String) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)
        let configured = base.withSymbolConfiguration(config) ?? base
        configured.isTemplate = true
        return configured
    }

    private static func dualDisplayTemplate(status: MBMenuBarStatus) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()

            // Primary local display on the left (crisp outline + stand)
            let leftScreen = NSRect(x: 1.5, y: 5.0, width: 6.5, height: 8.5)
            let leftPath = NSBezierPath(roundedRect: leftScreen, xRadius: 1.4, yRadius: 1.4)
            leftPath.lineWidth = 1.35
            leftPath.stroke()

            let leftStand = NSBezierPath()
            leftStand.move(to: NSPoint(x: 3.3, y: 3.2))
            leftStand.line(to: NSPoint(x: 6.2, y: 3.2))
            leftStand.lineWidth = 1.25
            leftStand.lineCapStyle = .round
            leftStand.stroke()

            // Secondary remote display on the right
            let rightScreen = NSRect(x: 10.0, y: 5.0, width: 6.5, height: 8.5)
            let rightPath = NSBezierPath(roundedRect: rightScreen, xRadius: 1.4, yRadius: 1.4)
            rightPath.lineWidth = 1.35

            switch status {
            case .idle:
                NSColor.labelColor.withAlphaComponent(0.55).setStroke()
                rightPath.setLineDash([2.0, 1.5], count: 2, phase: 0)
                rightPath.stroke()
            case .connected:
                rightPath.stroke()
                let rightStand = NSBezierPath()
                rightStand.move(to: NSPoint(x: 11.8, y: 3.2))
                rightStand.line(to: NSPoint(x: 14.7, y: 3.2))
                rightStand.lineWidth = 1.25
                rightStand.lineCapStyle = .round
                rightStand.stroke()

                // Subtle bridge dot between monitors showing ready border link
                let bridge = NSBezierPath(ovalIn: NSRect(x: 8.2, y: 8.4, width: 1.6, height: 1.6))
                bridge.fill()
            case .controllingRemote:
                rightPath.fill()
                rightPath.stroke()
                let rightStand = NSBezierPath()
                rightStand.move(to: NSPoint(x: 11.8, y: 3.2))
                rightStand.line(to: NSPoint(x: 14.7, y: 3.2))
                rightStand.lineWidth = 1.25
                rightStand.lineCapStyle = .round
                rightStand.stroke()
            case .permissionNeeded, .paused, .locked:
                rightPath.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}
