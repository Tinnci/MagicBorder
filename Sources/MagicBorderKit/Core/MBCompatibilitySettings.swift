import Foundation
import Observation

@MainActor
@Observable
public final class MBCompatibilitySettings {
    private enum Keys {
        static let shareClipboard = "compat.shareClipboard"
        static let transferFiles = "compat.transferFiles"
        static let switchByMouse = "compat.switchByMouse"
        static let blockCorners = "compat.blockCorners"
        static let moveMouseRelatively = "compat.moveMouseRelatively"
        static let matrixOneRow = "compat.matrixOneRow"
        static let matrixCircle = "compat.matrixCircle"
        static let messagePort = "compat.messagePort"
        static let clipboardPort = "compat.clipboardPort"
        static let securityKey = "compat.securityKey"
    }

    private let defaults = UserDefaults.standard

    public var shareClipboard: Bool {
        didSet { defaults.set(shareClipboard, forKey: Keys.shareClipboard) }
    }

    public var transferFiles: Bool {
        didSet { defaults.set(transferFiles, forKey: Keys.transferFiles) }
    }

    public var switchByMouse: Bool {
        didSet { defaults.set(switchByMouse, forKey: Keys.switchByMouse) }
    }

    public var blockCorners: Bool {
        didSet { defaults.set(blockCorners, forKey: Keys.blockCorners) }
    }

    public var moveMouseRelatively: Bool {
        didSet { defaults.set(moveMouseRelatively, forKey: Keys.moveMouseRelatively) }
    }

    public var matrixOneRow: Bool {
        didSet { defaults.set(matrixOneRow, forKey: Keys.matrixOneRow) }
    }

    public var matrixCircle: Bool {
        didSet { defaults.set(matrixCircle, forKey: Keys.matrixCircle) }
    }

    public var messagePort: UInt16 {
        didSet { defaults.set(Int(messagePort), forKey: Keys.messagePort) }
    }

    public var clipboardPort: UInt16 {
        didSet { defaults.set(Int(clipboardPort), forKey: Keys.clipboardPort) }
    }

    public var securityKey: String {
        didSet { defaults.set(securityKey, forKey: Keys.securityKey) }
    }

    public var validationMessage: String?

    public init() {
        shareClipboard = defaults.object(forKey: Keys.shareClipboard) as? Bool ?? true
        transferFiles = defaults.object(forKey: Keys.transferFiles) as? Bool ?? false
        switchByMouse = defaults.object(forKey: Keys.switchByMouse) as? Bool ?? true
        blockCorners = defaults.object(forKey: Keys.blockCorners) as? Bool ?? false
        moveMouseRelatively = defaults.object(forKey: Keys.moveMouseRelatively) as? Bool ?? false
        matrixOneRow = defaults.object(forKey: Keys.matrixOneRow) as? Bool ?? true
        matrixCircle = defaults.object(forKey: Keys.matrixCircle) as? Bool ?? false
        if defaults.object(forKey: Keys.messagePort) != nil {
            messagePort = UInt16(defaults.integer(forKey: Keys.messagePort))
        } else {
            messagePort = 15101
        }
        if defaults.object(forKey: Keys.clipboardPort) != nil {
            clipboardPort = UInt16(defaults.integer(forKey: Keys.clipboardPort))
        } else {
            clipboardPort = 15100
        }
        securityKey = defaults.string(forKey: Keys.securityKey) ?? ""
    }

    public func validateSecurityKey() -> Bool {
        let trimmed = securityKey.replacingOccurrences(of: " ", with: "")
        if trimmed.count < 16 {
            validationMessage = "Security Key 至少 16 位"
            return false
        }
        validationMessage = nil
        return true
    }
}
