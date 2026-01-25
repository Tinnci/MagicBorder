@preconcurrency import ApplicationServices
import SwiftUI

@MainActor
public class AccessibilityService: ObservableObject {
    @Published public var isTrusted: Bool = false

    public init() {
        checkStatus()
    }

    public func checkStatus() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        self.isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    public func promptForPermission() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Polling loop to check permission status periodically
    public func startPolling() {
        Task {
            while true {
                // Sleep for 1 second
                try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
                let currentStatus = AXIsProcessTrusted()
                if self.isTrusted != currentStatus {
                    self.isTrusted = currentStatus
                }
            }
        }
    }
}
