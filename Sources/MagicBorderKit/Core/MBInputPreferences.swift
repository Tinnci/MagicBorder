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

/// Hardware key + modifier binding stored in user preferences.
public struct MBHotkeyBinding: Codable, Equatable, Sendable {
    public static let relevantModifierMask: CGEventFlags = [
        .maskControl,
        .maskAlternate,
        .maskCommand,
        .maskShift,
    ]

    public var keyCode: Int64
    public var modifierRawValue: UInt64

    public init(keyCode: Int64, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.modifierRawValue = flags.intersection(Self.relevantModifierMask).rawValue
    }

    public var flags: CGEventFlags {
        CGEventFlags(rawValue: self.modifierRawValue).intersection(Self.relevantModifierMask)
    }

    public func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        self.keyCode == keyCode && flags.intersection(Self.relevantModifierMask) == self.flags
    }

    public var displayLabel: String {
        var prefix = ""
        let resolved = self.flags
        if resolved.contains(.maskControl) { prefix += "⌃" }
        if resolved.contains(.maskAlternate) { prefix += "⌥" }
        if resolved.contains(.maskShift) { prefix += "⇧" }
        if resolved.contains(.maskCommand) { prefix += "⌘" }
        return prefix + (Self.keyNameMap[self.keyCode] ?? "Key \(self.keyCode)")
    }

    private static let keyNameMap: [Int64: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3",
        21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]",
        31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 40: "K", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

/// Complete set of customizable global hardware hotkeys.
public struct MBHotkeyConfiguration: Codable, Equatable, Sendable {
    public var slot1: MBHotkeyBinding
    public var slot2: MBHotkeyBinding
    public var slot3: MBHotkeyBinding
    public var slot4: MBHotkeyBinding
    public var toggleCursorLock: MBHotkeyBinding
    public var toggleInputPause: MBHotkeyBinding
    public var lockAllScreens: MBHotkeyBinding

    public static let `default`: Self = {
        let ctrlOpt: CGEventFlags = [.maskControl, .maskAlternate]
        let ctrlOptCmd: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        return MBHotkeyConfiguration(
            slot1: MBHotkeyBinding(keyCode: 18, flags: ctrlOpt),
            slot2: MBHotkeyBinding(keyCode: 19, flags: ctrlOpt),
            slot3: MBHotkeyBinding(keyCode: 20, flags: ctrlOpt),
            slot4: MBHotkeyBinding(keyCode: 21, flags: ctrlOpt),
            toggleCursorLock: MBHotkeyBinding(keyCode: 37, flags: ctrlOpt),
            toggleInputPause: MBHotkeyBinding(keyCode: 35, flags: ctrlOpt),
            lockAllScreens: MBHotkeyBinding(keyCode: 37, flags: ctrlOptCmd))
    }()
}

/// Semantic actions triggered by global hardware keybindings.
public enum MBShortcutAction: Equatable, Sendable {
    case switchToSlot(Int)
    case toggleCursorLock
    case toggleInputPause
    case lockAllScreens
}

/// Snapshot of tap-relevant preferences synchronized lock-free onto the `CGEventTap` callback.
public struct MBTapConfiguration: Equatable, Sendable {
    public var wrapCursor: Bool
    public var escapeMode: MBEscapeMode
    public var globalHotkeysEnabled: Bool
    public var hotkeys: MBHotkeyConfiguration

    public init(
        wrapCursor: Bool = true,
        escapeMode: MBEscapeMode = .doubleTapEsc,
        globalHotkeysEnabled: Bool = true,
        hotkeys: MBHotkeyConfiguration = .default
    ) {
        self.wrapCursor = wrapCursor
        self.escapeMode = escapeMode
        self.globalHotkeysEnabled = globalHotkeysEnabled
        self.hotkeys = hotkeys
    }
}

/// Pure, layout-independent key matcher for global shortcuts and Escape-return chords.
public enum MBShortcutMatcher: Sendable {
    public static let doubleTapWindow: TimeInterval = 0.35
    private static let escapeKeyCode: Int64 = 53

    public static func matchShortcut(
        keyCode: Int64,
        flags: CGEventFlags,
        enabled: Bool,
        configuration: MBHotkeyConfiguration = .default
    ) -> MBShortcutAction? {
        guard enabled else { return nil }
        if configuration.lockAllScreens.matches(keyCode: keyCode, flags: flags) {
            return .lockAllScreens
        }
        if configuration.toggleCursorLock.matches(keyCode: keyCode, flags: flags) {
            return .toggleCursorLock
        }
        if configuration.toggleInputPause.matches(keyCode: keyCode, flags: flags) {
            return .toggleInputPause
        }
        let slotBindings = [
            configuration.slot1,
            configuration.slot2,
            configuration.slot3,
            configuration.slot4,
        ]
        for (index, binding) in slotBindings.enumerated() where binding.matches(keyCode: keyCode, flags: flags) {
            return .switchToSlot(index)
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
