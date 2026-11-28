import AppKit
import MagicBorderKit
import Observation
import ServiceManagement
import SwiftUI
import os

@MainActor
@Observable
final class MBAppController {
    private enum Keys {
        static let captureInput = "captureInput"
        static let hideDockIcon = "ui.hideDockIcon"
        static let overlayEnabled = "dragDropOverlayEnabled"
        static let overlayShowDevice = "dragDropOverlayShowDevice"
        static let overlayShowProgress = "dragDropOverlayShowProgress"
        static let overlayScale = "dragDropOverlayScale"
        static let overlayPosition = "dragDropOverlayPosition"
    }

    let accessibilityService: MBAccessibilityService
    let inputManager: MBInputManager
    let networkManager: MBNetworkManager
    let overlayPreferences: MBOverlayPreferencesStore
    let toastPresenter = MBToastPresenter()
    let dragDropPresenter = MBDragDropOverlayPresenter()

    var captureInput: Bool {
        didSet {
            UserDefaults.standard.set(self.captureInput, forKey: Keys.captureInput)
            self.syncInputCapture()
        }
    }

    var hideDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(self.hideDockIcon, forKey: Keys.hideDockIcon)
            self.applyActivationPolicy()
        }
    }

    var launchAtLogin: Bool
    var launchAtLoginError: String?

    private var observationTask: Task<Void, Never>?
    private var lastPresentedToast: MBToastEvent?

    init() {
        let accessibility = MBAccessibilityService()
        let input = MBInputManager()
        let network = MBNetworkManager(
            localName: Host.current().localizedName ?? "Unknown Mac",
            localID: UUID(),
            localNumericID: .random(in: 1000...999999),
            compatibilitySettings: MBCompatibilitySettings(),
            inputManager: input,
            isFrontmostAppFullscreen: { Self.isOtherAppFullscreenOnMainDisplay() },
            startDiscovery: true,
            startTransports: true,
            startClipboardMonitoring: true)

        self.accessibilityService = accessibility
        self.inputManager = input
        self.networkManager = network
        self.overlayPreferences = MBOverlayPreferencesStore()
        self.captureInput = UserDefaults.standard.object(forKey: Keys.captureInput) as? Bool ?? true
        self.hideDockIcon = UserDefaults.standard.object(forKey: Keys.hideDockIcon) as? Bool ?? false
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        accessibility.startPolling()
        self.applyActivationPolicy()
        self.syncAppState()
        self.startObservationLoop()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        self.launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
            self.launchAtLoginError = error.localizedDescription
        }
    }

    var menuBarStatus: MBMenuBarStatus {
        if !self.accessibilityService.isTrusted {
            return .permissionNeeded
        }
        if self.networkManager.isInputPaused || !self.captureInput {
            return .paused
        }
        if self.networkManager.isCursorLocked {
            return .locked
        }
        if self.networkManager.activeMachineId != nil {
            return .controllingRemote
        }
        if !self.networkManager.connectedMachines.isEmpty {
            return .connected
        }
        return .idle
    }

    var menuBarIconName: String {
        switch self.menuBarStatus {
        case .permissionNeeded:
            return "exclamationmark.triangle"
        case .paused:
            return "pause.circle"
        case .locked:
            return "lock.display"
        case .controllingRemote:
            return "arrow.right.circle.fill"
        case .connected, .idle:
            return "display.2"
        }
    }

    var menuBarIconImage: NSImage {
        MBMenuBarIconRenderer.image(for: self.menuBarStatus)
    }

    func previewDragDropOverlay() {
        let prefs = self.effectiveOverlayPreferences(for: nil)
        self.dragDropPresenter.show(
            state: .dropping,
            sourceName: self.networkManager.localDisplayName,
            fileSummary: "Preview.zip",
            progress: 0.65,
            preferences: prefs)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.syncDragDropOverlay()
        }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(self.hideDockIcon ? .accessory : .regular)
    }

    private func syncInputCapture() {
        let shouldCapture = self.captureInput && self.accessibilityService.isTrusted
        self.inputManager.toggleInterception(shouldCapture)
    }

    private func syncAppState() {
        self.syncInputCapture()
        self.networkManager.applyCompatibilitySettings()
        let currentToast = self.networkManager.toast
        if currentToast != self.lastPresentedToast {
            self.lastPresentedToast = currentToast
            if let currentToast {
                self.toastPresenter.show(
                    message: currentToast.localizedMessage,
                    systemImage: currentToast.defaultSystemImage)
            } else {
                self.toastPresenter.hide()
            }
        }
        self.syncDragDropOverlay()
    }

    private func syncDragDropOverlay() {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: Keys.overlayEnabled) as? Bool ?? true
        let bridge = self.networkManager.clipboardBridge
        guard enabled, let state = bridge.dragDropState else {
            self.dragDropPresenter.hide()
            return
        }
        let prefs = self.effectiveOverlayPreferences(for: bridge.dragDropSourceName)
        self.dragDropPresenter.show(
            state: state,
            sourceName: bridge.dragDropSourceName,
            fileSummary: bridge.dragDropFileSummary,
            progress: bridge.dragDropProgress,
            preferences: prefs)
    }

    private func effectiveOverlayPreferences(for sourceName: String?) -> MBOverlayPreferences {
        let defaults = UserDefaults.standard
        let defaultPrefs = MBOverlayPreferences(
            showDevice: defaults.object(forKey: Keys.overlayShowDevice) as? Bool ?? true,
            showProgress: defaults.object(forKey: Keys.overlayShowProgress) as? Bool ?? true,
            scale: defaults.object(forKey: Keys.overlayScale) as? Double ?? 1.0,
            position: MBOverlayPosition(rawValue: defaults.string(forKey: Keys.overlayPosition) ?? "top") ?? .top)
        let deviceName = sourceName ?? self.networkManager.localDisplayName
        return self.overlayPreferences.preferences(for: deviceName, default: defaultPrefs)
    }

    private func startObservationLoop() {
        self.observationTask?.cancel()
        self.observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                let pending = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: nil)
                let resumePending: @Sendable () -> Void = {
                    let cont = pending.withLock { slot -> CheckedContinuation<Void, Never>? in
                        let current = slot
                        slot = nil
                        return current
                    }
                    cont?.resume()
                }
                await withTaskCancellationHandler {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        pending.withLock { $0 = continuation }
                        withObservationTracking {
                            self.syncAppState()
                        } onChange: {
                            resumePending()
                        }
                    }
                } onCancel: {
                    resumePending()
                }
                await Task.yield()
            }
        }
    }

    private static func isOtherAppFullscreenOnMainDisplay() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
            frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.frame,
            let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let targetPID = Int(frontApp.processIdentifier)
        return windowList.contains { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                ownerPID == targetPID,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return false }
            return abs(bounds.width - screenFrame.width) < 2
                && abs(bounds.height - screenFrame.height) < 2
        }
    }
}
