import Foundation
import Observation

@MainActor
@Observable
public final class MBCompatibilitySettings {
    public var shareClipboard: Bool = true
    public var transferFiles: Bool = false
    public var switchByMouse: Bool = true
    public var blockCorners: Bool = false
    public var moveMouseRelatively: Bool = false
    public var matrixOneRow: Bool = true
    public var matrixCircle: Bool = false
    public var messagePort: UInt16 = 15101
    public var clipboardPort: UInt16 = 15100
    public var securityKey: String = ""
    public var validationMessage: String?

    public init() {}

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
