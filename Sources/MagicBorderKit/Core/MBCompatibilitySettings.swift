public import Foundation
public import Observation

@MainActor
@Observable
public final class MBCompatibilitySettings {
    public enum KeyValidationStatus: Equatable, Sendable {
        case valid
        case tooShort
    }

    private enum Keys {
        static let protocolMode = "compat.protocolMode"
        static let shareClipboard = "compat.shareClipboard"
        static let transferFiles = "compat.transferFiles"
        static let switchByMouse = "compat.switchByMouse"
        static let blockCorners = "compat.blockCorners"
        static let moveMouseRelatively = "compat.moveMouseRelatively"
        static let centerCursorOnManualSwitch = "compat.centerCursorOnManualSwitch"
        static let edgeSwitchLockSeconds = "compat.edgeSwitchLockSeconds"
        static let edgeSwitchSafeMargin = "compat.edgeSwitchSafeMargin"
        static let edgeCrossingModifier = "compat.edgeCrossingModifier"
        static let edgeDwellSeconds = "compat.edgeDwellSeconds"
        static let escapeMode = "compat.escapeMode"
        static let modifierRemapMode = "compat.modifierRemapMode"
        static let invertRemoteScroll = "compat.invertRemoteScroll"
        static let remoteScrollSpeed = "compat.remoteScrollSpeed"
        static let ignoreConcealedClipboard = "compat.ignoreConcealedClipboard"
        static let maxClipboardSizeMB = "compat.maxClipboardSizeMB"
        static let globalHotkeysEnabled = "compat.globalHotkeysEnabled"
        static let lockCursorInFullscreenApps = "compat.lockCursorInFullscreenApps"
        static let onboardingCompleted = "compat.onboardingCompleted"
        static let matrixOneRow = "compat.matrixOneRow"
        static let matrixCircle = "compat.matrixCircle"
        static let messagePort = "compat.messagePort"
        static let clipboardPort = "compat.clipboardPort"
        static let securityKey = "compat.securityKey"
        static let wrapCursor = "compat.wrapCursor"
    }

    private let defaults: UserDefaults

    public var protocolMode: MBProtocolMode {
        didSet { self.defaults.set(self.protocolMode.rawValue, forKey: Keys.protocolMode) }
    }

    public var shareClipboard: Bool {
        didSet { self.defaults.set(self.shareClipboard, forKey: Keys.shareClipboard) }
    }

    public var transferFiles: Bool {
        didSet { self.defaults.set(self.transferFiles, forKey: Keys.transferFiles) }
    }

    public var switchByMouse: Bool {
        didSet { self.defaults.set(self.switchByMouse, forKey: Keys.switchByMouse) }
    }

    public var blockCorners: Bool {
        didSet { self.defaults.set(self.blockCorners, forKey: Keys.blockCorners) }
    }

    public var moveMouseRelatively: Bool {
        didSet { self.defaults.set(self.moveMouseRelatively, forKey: Keys.moveMouseRelatively) }
    }

    public var centerCursorOnManualSwitch: Bool {
        didSet { self.defaults.set(self.centerCursorOnManualSwitch, forKey: Keys.centerCursorOnManualSwitch) }
    }

    public var edgeSwitchLockSeconds: Double {
        didSet { self.defaults.set(self.edgeSwitchLockSeconds, forKey: Keys.edgeSwitchLockSeconds) }
    }

    public var edgeSwitchSafeMargin: Double {
        didSet { self.defaults.set(self.edgeSwitchSafeMargin, forKey: Keys.edgeSwitchSafeMargin) }
    }

    public var edgeCrossingModifier: MBEdgeCrossingModifier {
        didSet { self.defaults.set(self.edgeCrossingModifier.rawValue, forKey: Keys.edgeCrossingModifier) }
    }

    public var edgeDwellSeconds: Double {
        didSet { self.defaults.set(self.edgeDwellSeconds, forKey: Keys.edgeDwellSeconds) }
    }

    public var escapeMode: MBEscapeMode {
        didSet { self.defaults.set(self.escapeMode.rawValue, forKey: Keys.escapeMode) }
    }

    public var modifierRemapMode: MBModifierRemapMode {
        didSet { self.defaults.set(self.modifierRemapMode.rawValue, forKey: Keys.modifierRemapMode) }
    }

    public var invertRemoteScroll: Bool {
        didSet { self.defaults.set(self.invertRemoteScroll, forKey: Keys.invertRemoteScroll) }
    }

    public var remoteScrollSpeed: Double {
        didSet { self.defaults.set(self.remoteScrollSpeed, forKey: Keys.remoteScrollSpeed) }
    }

    public var ignoreConcealedClipboard: Bool {
        didSet { self.defaults.set(self.ignoreConcealedClipboard, forKey: Keys.ignoreConcealedClipboard) }
    }

    public var maxClipboardSizeMB: Int {
        didSet { self.defaults.set(self.maxClipboardSizeMB, forKey: Keys.maxClipboardSizeMB) }
    }

    public var globalHotkeysEnabled: Bool {
        didSet { self.defaults.set(self.globalHotkeysEnabled, forKey: Keys.globalHotkeysEnabled) }
    }

    public var lockCursorInFullscreenApps: Bool {
        didSet { self.defaults.set(self.lockCursorInFullscreenApps, forKey: Keys.lockCursorInFullscreenApps) }
    }

    public var onboardingCompleted: Bool {
        didSet { self.defaults.set(self.onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }

    public var matrixOneRow: Bool {
        didSet { self.defaults.set(self.matrixOneRow, forKey: Keys.matrixOneRow) }
    }

    public var matrixCircle: Bool {
        didSet { self.defaults.set(self.matrixCircle, forKey: Keys.matrixCircle) }
    }

    public var messagePort: UInt16 {
        didSet { self.defaults.set(Int(self.messagePort), forKey: Keys.messagePort) }
    }

    public var clipboardPort: UInt16 {
        didSet { self.defaults.set(Int(self.clipboardPort), forKey: Keys.clipboardPort) }
    }

    public var securityKey: String {
        didSet { self.defaults.set(self.securityKey, forKey: Keys.securityKey) }
    }

    public var wrapCursor: Bool {
        didSet { self.defaults.set(self.wrapCursor, forKey: Keys.wrapCursor) }
    }

    public var validationStatus: KeyValidationStatus?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.protocolMode =
            defaults.string(forKey: Keys.protocolMode).flatMap(MBProtocolMode.init) ?? .mwbCompatibility
        self.shareClipboard = defaults.object(forKey: Keys.shareClipboard) as? Bool ?? true
        self.transferFiles = defaults.object(forKey: Keys.transferFiles) as? Bool ?? false
        self.switchByMouse = defaults.object(forKey: Keys.switchByMouse) as? Bool ?? true
        self.blockCorners = defaults.object(forKey: Keys.blockCorners) as? Bool ?? false
        self.moveMouseRelatively = defaults.object(forKey: Keys.moveMouseRelatively) as? Bool ?? false
        self.centerCursorOnManualSwitch =
            defaults.object(forKey: Keys.centerCursorOnManualSwitch) as? Bool ?? true
        self.edgeSwitchLockSeconds = defaults.object(forKey: Keys.edgeSwitchLockSeconds) as? Double ?? 0.4
        self.edgeSwitchSafeMargin = defaults.object(forKey: Keys.edgeSwitchSafeMargin) as? Double ?? 16
        self.edgeCrossingModifier =
            defaults.string(forKey: Keys.edgeCrossingModifier).flatMap(MBEdgeCrossingModifier.init) ?? .none
        self.edgeDwellSeconds = defaults.object(forKey: Keys.edgeDwellSeconds) as? Double ?? 0.0
        self.escapeMode = defaults.string(forKey: Keys.escapeMode).flatMap(MBEscapeMode.init) ?? .doubleTapEsc
        self.modifierRemapMode =
            defaults.string(forKey: Keys.modifierRemapMode).flatMap(MBModifierRemapMode.init) ?? .standard
        self.invertRemoteScroll = defaults.object(forKey: Keys.invertRemoteScroll) as? Bool ?? false
        self.remoteScrollSpeed = defaults.object(forKey: Keys.remoteScrollSpeed) as? Double ?? 1.0
        self.ignoreConcealedClipboard =
            defaults.object(forKey: Keys.ignoreConcealedClipboard) as? Bool ?? true
        let rawMaxSize = defaults.integer(forKey: Keys.maxClipboardSizeMB)
        self.maxClipboardSizeMB = rawMaxSize > 0 ? rawMaxSize : 10
        self.globalHotkeysEnabled = defaults.object(forKey: Keys.globalHotkeysEnabled) as? Bool ?? true
        self.lockCursorInFullscreenApps =
            defaults.object(forKey: Keys.lockCursorInFullscreenApps) as? Bool ?? false
        self.onboardingCompleted = defaults.object(forKey: Keys.onboardingCompleted) as? Bool ?? false
        self.matrixOneRow = defaults.object(forKey: Keys.matrixOneRow) as? Bool ?? true
        self.matrixCircle = defaults.object(forKey: Keys.matrixCircle) as? Bool ?? false
        self.messagePort = Self.portValue(forKey: Keys.messagePort, defaultValue: 15101, defaults: defaults)
        self.clipboardPort = Self.portValue(forKey: Keys.clipboardPort, defaultValue: 15100, defaults: defaults)
        self.securityKey = defaults.string(forKey: Keys.securityKey) ?? ""
        self.wrapCursor = defaults.object(forKey: Keys.wrapCursor) as? Bool ?? true
    }

    public func validateSecurityKey() -> Bool {
        let trimmed = self.securityKey.replacingOccurrences(of: " ", with: "")
        if trimmed.count < 16 {
            self.validationStatus = .tooShort
            return false
        }
        self.validationStatus = .valid
        return true
    }

    private static func portValue(forKey key: String, defaultValue: UInt16, defaults: UserDefaults) -> UInt16 {
        let value = defaults.integer(forKey: key)
        guard defaults.object(forKey: key) != nil,
            value > 0,
            value <= Int(UInt16.max)
        else { return defaultValue }
        return UInt16(value)
    }
}
