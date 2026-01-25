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

    public var validationMessage: String?

    public init() {
        self.shareClipboard = self.defaults.object(forKey: Keys.shareClipboard) as? Bool ?? true
        self.transferFiles = self.defaults.object(forKey: Keys.transferFiles) as? Bool ?? false
        self.switchByMouse = self.defaults.object(forKey: Keys.switchByMouse) as? Bool ?? true
        self.blockCorners = self.defaults.object(forKey: Keys.blockCorners) as? Bool ?? false
        self.moveMouseRelatively = self.defaults.object(forKey: Keys.moveMouseRelatively) as? Bool ?? false
        self.matrixOneRow = self.defaults.object(forKey: Keys.matrixOneRow) as? Bool ?? true
        self.matrixCircle = self.defaults.object(forKey: Keys.matrixCircle) as? Bool ?? false
        if self.defaults.object(forKey: Keys.messagePort) != nil {
            self.messagePort = UInt16(self.defaults.integer(forKey: Keys.messagePort))
        } else {
            self.messagePort = 15101
        }
        if self.defaults.object(forKey: Keys.clipboardPort) != nil {
            self.clipboardPort = UInt16(self.defaults.integer(forKey: Keys.clipboardPort))
        } else {
            self.clipboardPort = 15100
        }
        self.securityKey = self.defaults.string(forKey: Keys.securityKey) ?? ""
    }

    public func validateSecurityKey() -> Bool {
        let trimmed = self.securityKey.replacingOccurrences(of: " ", with: "")
        if trimmed.count < 16 {
            self.validationMessage = "Security Key 至少 16 位"
            return false
        }
        self.validationMessage = nil
        return true
    }
}
