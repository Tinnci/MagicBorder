import AppKit
@preconcurrency import ApplicationServices
public import Observation

@MainActor
@Observable
public final class MBAccessibilityService: Observation.Observable {
    public var isTrusted: Bool = false
    private let pollingTask = CancellableTaskSlot()

    public init() {
        self.checkStatus()
    }

    deinit {
        self.pollingTask.cancel()
    }

    public func checkStatus() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        self.isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    /// Prompts the user with a system alert if accessibility permission is missing.
    public func promptForPermission() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        self.isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings directly to the Accessibility privacy pane.
    public func openSystemSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    /// Idempotent polling loop to check permission status periodically.
    public func startPolling(interval: Duration = .seconds(1)) {
        guard !self.pollingTask.isActive else { return }
        let task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { break }
                let currentStatus = AXIsProcessTrusted()
                if self.isTrusted != currentStatus {
                    self.isTrusted = currentStatus
                }
            }
        }
        self.pollingTask.replace(with: task)
    }

    public func stopPolling() {
        self.pollingTask.cancel()
    }
}
