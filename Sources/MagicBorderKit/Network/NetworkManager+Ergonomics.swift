import Foundation

extension MBNetworkManager {
    public var isCursorLocked: Bool {
        self.sessionCoordinator.isCursorLocked
    }

    public var isInputPaused: Bool {
        self.sessionCoordinator.isInputPaused
    }

    public func toggleCursorLock() {
        self.sessionCoordinator.toggleCursorLock()
    }

    public func setInputPaused(_ paused: Bool) {
        guard self.sessionCoordinator.isInputPaused != paused else { return }
        self.sessionCoordinator.isInputPaused = paused
        if paused, self.sessionCoordinator.activeMachineId != nil {
            self.forceReturnToLocal(reason: "paused")
        }
        self.showToast(paused ? .inputPaused : .inputResumed)
    }

    public func toggleInputPause() {
        self.setInputPaused(!self.sessionCoordinator.isInputPaused)
    }

    public func pushCurrentClipboard() {
        self.clipboardBridge.pushCurrentClipboard(settings: self.compatibilitySettings)
    }

    public func rescanNetwork() {
        self.discoveryService?.startSubnetScanning(port: self.compatibilitySettings.messagePort)
    }

    public func localIPv4Addresses() -> [String] {
        MBConnectionDoctor.localIPv4Addresses()
    }

    public func runConnectionDoctor(host: String) async -> MBConnectionDoctor.Report {
        await MBConnectionDoctor.diagnose(
            host: host,
            protocolMode: self.protocolMode,
            securityKey: self.compatibilitySettings.securityKey,
            messagePort: self.compatibilitySettings.messagePort,
            clipboardPort: self.compatibilitySettings.clipboardPort)
    }

    public func redactedDiagnosticsText() -> String {
        MBConnectionDoctor.redact(
            logs: self.pairingDebugLog,
            securityKey: self.compatibilitySettings.securityKey)
    }

    public func handleShortcut(_ action: MBShortcutAction) {
        switch action {
        case .switchToSlot(let index):
            let machines = self.visibleMachines()
            guard machines.indices.contains(index) else { return }
            let target = machines[index]
            if target.id == MBNetworkManager.localMachineUUID {
                self.forceReturnToLocal(reason: "shortcut")
            } else {
                self.requestSwitch(to: target.id)
            }
        case .toggleCursorLock:
            self.toggleCursorLock()
        case .toggleInputPause:
            self.toggleInputPause()
        }
    }

    public func handleSystemSleepOrLock() {
        if self.sessionCoordinator.activeMachineId != nil {
            self.forceReturnToLocal(reason: "system-sleep-or-lock")
        }
    }
}
