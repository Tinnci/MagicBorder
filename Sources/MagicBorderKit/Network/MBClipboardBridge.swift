public import Foundation
public import Observation

@MainActor
@Observable
public final class MBClipboardBridge: Observation.Observable {
    public var dragDropState: MBDragDropState?
    public var dragDropSourceName: String?
    public var dragDropFileSummary: String?
    public var dragDropProgress: Double?

    private let pasteboard: any PasteboardAccessing
    private let hasConnectedPeers: () -> Bool
    private let ignoreNextLocalChange: () -> Void
    private let emitToast: (MBToastEvent) -> Void
    private let sendClipboardText: (String) -> Void
    private let sendClipboardImage: (Data) -> Void
    private let sendFileDrop: ([URL]) -> Bool
    private let clearPresentationTask = CancellableTaskSlot()

    public init(
        pasteboard: any PasteboardAccessing = SystemPasteboard(),
        hasConnectedPeers: @escaping () -> Bool = { true },
        ignoreNextLocalChange: @escaping () -> Void = {},
        emitToast: @escaping (MBToastEvent) -> Void,
        sendClipboardText: @escaping (String) -> Void,
        sendClipboardImage: @escaping (Data) -> Void,
        sendFileDrop: @escaping ([URL]) -> Bool
    ) {
        self.pasteboard = pasteboard
        self.hasConnectedPeers = hasConnectedPeers
        self.ignoreNextLocalChange = ignoreNextLocalChange
        self.emitToast = emitToast
        self.sendClipboardText = sendClipboardText
        self.sendClipboardImage = sendClipboardImage
        self.sendFileDrop = sendFileDrop
    }

    deinit {
        self.clearPresentationTask.cancel()
    }

    public func handleLocalPasteboard(
        _ content: MBPasteboardContent,
        settings: MBCompatibilitySettings,
        isManual: Bool = false
    ) {
        guard settings.shareClipboard, self.hasConnectedPeers() else { return }
        let maxBytes = max(1, settings.maxClipboardSizeMB) * 1_048_576

        switch content {
        case .text(let text):
            guard text.utf8.count <= maxBytes else {
                self.emitToast(.clipboardTooLarge(settings.maxClipboardSizeMB))
                return
            }
            self.sendClipboardText(text)
            if isManual {
                self.emitToast(.clipboardSyncedText)
            }
        case .image(let data):
            guard data.count <= maxBytes else {
                self.emitToast(.clipboardTooLarge(settings.maxClipboardSizeMB))
                return
            }
            self.sendClipboardImage(data)
            if isManual {
                self.emitToast(.clipboardSyncedImage)
            }
        case .files(let urls):
            guard settings.transferFiles else { return }
            if self.sendFileDrop(urls), isManual {
                self.emitToast(.clipboardSyncedFiles)
            }
        }
    }

    public func pushCurrentClipboard(settings: MBCompatibilitySettings) {
        guard self.hasConnectedPeers() else {
            self.emitToast(.noConnectedDevices)
            return
        }
        guard settings.shareClipboard else { return }
        guard !(settings.ignoreConcealedClipboard && self.pasteboard.isConcealedOrTransient) else {
            self.emitToast(.clipboardEmpty)
            return
        }
        if settings.transferFiles, let urls = self.pasteboard.readFileURLs(), !urls.isEmpty {
            self.handleLocalPasteboard(.files(urls), settings: settings, isManual: true)
            return
        }
        if let string = self.pasteboard.readString(), !string.isEmpty {
            self.handleLocalPasteboard(.text(string), settings: settings, isManual: true)
            return
        }
        if let png = self.pasteboard.readPNGData(), !png.isEmpty {
            self.handleLocalPasteboard(.image(png), settings: settings, isManual: true)
            return
        }
        self.emitToast(.clipboardEmpty)
    }

    public func handleTransportEvent(
        _ event: MBTransportEvent,
        settings: MBCompatibilitySettings
    ) -> Bool {
        switch event {
        case .clipboardText(let text):
            guard settings.shareClipboard else { return true }
            self.ignoreNextLocalChange()
            self.pasteboard.writeString(text)
            self.emitToast(.clipboardReceivedText)
            return true
        case .clipboardImage(let data):
            guard settings.shareClipboard else { return true }
            self.ignoreNextLocalChange()
            if self.pasteboard.writeImageData(data) {
                self.emitToast(.clipboardReceivedImage)
            }
            return true
        case .clipboardFiles(let urls):
            guard settings.shareClipboard, settings.transferFiles else { return true }
            self.ignoreNextLocalChange()
            self.pasteboard.writeFileURLs(urls)
            self.dragDropFileSummary = self.makeFileSummary(urls)
            self.dragDropProgress = 1.0
            self.emitToast(.clipboardReceivedFiles)
            self.schedulePresentationClear()
            return true
        case .dragDropStateChanged(let state, let sourceName):
            guard settings.transferFiles else { return true }
            self.dragDropState = state
            self.dragDropSourceName = sourceName
            self.dragDropProgress = nil
            if state == nil {
                self.dragDropFileSummary = nil
            }
            return true
        default:
            return false
        }
    }

    private func schedulePresentationClear() {
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self else { return }
            self.clearPresentation()
        }
        self.clearPresentationTask.replace(with: task)
    }

    private func clearPresentation() {
        self.dragDropState = nil
        self.dragDropSourceName = nil
        self.dragDropFileSummary = nil
        self.dragDropProgress = nil
    }

    private func makeFileSummary(_ urls: [URL]) -> String? {
        guard let first = urls.first else { return nil }
        if urls.count == 1 {
            return first.lastPathComponent
        }
        return "\(first.lastPathComponent) +\(urls.count - 1)"
    }
}
