@preconcurrency import ApplicationServices
import Observation
import SwiftUI

@MainActor
@Observable
public class MBAccessibilityService: Observation.Observable {
    public var isTrusted: Bool = false

    public init() {
        self.checkStatus()
    }

    public func checkStatus() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        self.isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    /// Prompts the user with system alert if permission is missing (2026 best practice)
    public func promptForPermission() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        self.isTrusted = granted
    }

    /// Opens System Settings directly to Accessibility privacy pane (2026 UX best practice)
    public func openSystemSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    /// Polling loop to check permission status periodically
    public func startPolling() {
        Task {
            while true {
                // Sleep for 1 second
                try? await Task.sleep(nanoseconds: 1 * 1000000000)
                let currentStatus = AXIsProcessTrusted()
                if self.isTrusted != currentStatus {
                    self.isTrusted = currentStatus
                }
            }
        }
    }
}
