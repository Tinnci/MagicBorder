public import CoreGraphics
public import Foundation

/// Controls how pressing Escape exits remote control and returns to the local Mac.
public enum MBEscapeMode: String, CaseIterable, Codable, Sendable {
    /// Tap Escape twice within 350ms to return home; single Escape goes to the remote machine.
    case doubleTapEsc
    /// Press Control+Option+Escape to return home; plain Escape always goes to the remote machine.
    case controlOptionEsc
    /// Single Escape press immediately returns to the local Mac.
    case singleEsc
}

/// Optional modifier key required while hitting a screen edge to trigger a switch.
public enum MBEdgeCrossingModifier: String, CaseIterable, Codable, Sendable {
    case none
    case command
    case option
    case control

    public func matches(_ flags: CGEventFlags) -> Bool {
        switch self {
        case .none:
            true
        case .command:
            flags.contains(.maskCommand)
        case .option:
            flags.contains(.maskAlternate)
        case .control:
            flags.contains(.maskControl)
        }
    }
}

/// Modifier key mapping applied when forwarding keyboard input to Windows (MWB) peers.
public enum MBModifierRemapMode: String, CaseIterable, Codable, Sendable {
    /// Preserve raw physical modifier roles (Option->Alt, Control->Ctrl, Command->Win).
    case standard
    /// Swap Command and Control so Mac shortcuts like Cmd+C behave like Ctrl+C on Windows.
    case swapCommandControl
}

/// Semantic actions triggered by global hardware keybindings.
public enum MBShortcutAction: Equatable, Sendable {
    case switchToSlot(Int)
    case toggleCursorLock
    case toggleInputPause
}

/// Snapshot of tap-relevant preferences synchronized lock-free onto the `CGEventTap` callback.
public struct MBTapConfiguration: Equatable, Sendable {
    public var wrapCursor: Bool
    public var escapeMode: MBEscapeMode
    public var globalHotkeysEnabled: Bool

    public init(
        wrapCursor: Bool = true,
        escapeMode: MBEscapeMode = .doubleTapEsc,
        globalHotkeysEnabled: Bool = true
    ) {
        self.wrapCursor = wrapCursor
        self.escapeMode = escapeMode
        self.globalHotkeysEnabled = globalHotkeysEnabled
    }
}

/// Pure, layout-independent key matcher for global shortcuts and Escape-return chords.
public enum MBShortcutMatcher: Sendable {
    public static let doubleTapWindow: TimeInterval = 0.35

    private static let escapeKeyCode: Int64 = 53
    private static let slotKeyCodes: [Int64: Int] = [
        18: 0,  // 1
        19: 1,  // 2
        20: 2,  // 3
        21: 3,  // 4
    ]
    private static let lockKeyCode: Int64 = 37  // L
    private static let pauseKeyCode: Int64 = 35  // P

    public static func matchShortcut(
        keyCode: Int64,
        flags: CGEventFlags,
        enabled: Bool
    ) -> MBShortcutAction? {
        guard enabled else { return nil }
        let required: CGEventFlags = [.maskControl, .maskAlternate]
        guard flags.contains(required), !flags.contains(.maskCommand) else { return nil }

        if let slot = Self.slotKeyCodes[keyCode] {
            return .switchToSlot(slot)
        }
        if keyCode == Self.lockKeyCode {
            return .toggleCursorLock
        }
        if keyCode == Self.pauseKeyCode {
            return .toggleInputPause
        }
        return nil
    }

    public static func shouldTriggerEscape(
        mode: MBEscapeMode,
        keyCode: Int64,
        flags: CGEventFlags,
        now: TimeInterval,
        lastEscTap: inout TimeInterval
    ) -> Bool {
        guard keyCode == Self.escapeKeyCode else { return false }
        switch mode {
        case .singleEsc:
            return true
        case .controlOptionEsc:
            return flags.contains([.maskControl, .maskAlternate])
        case .doubleTapEsc:
            if lastEscTap > 0, now - lastEscTap <= Self.doubleTapWindow {
                lastEscTap = 0
                return true
            }
            lastEscTap = now
            return false
        }
    }
}
