import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class MBClipboardBridge: Observation.Observable {
    public var dragDropState: MBDragDropState?
    public var dragDropSourceName: String?
    public var dragDropFileSummary: String?
    public var dragDropProgress: Double?

    private let showToast: (String, String) -> Void
    private let sendClipboardText: (String) -> Void
    private let sendClipboardImage: (Data) -> Void
    private let sendFileDrop: ([URL]) -> Void

    public init(
        showToast: @escaping (String, String) -> Void,
        sendClipboardText: @escaping (String) -> Void,
        sendClipboardImage: @escaping (Data) -> Void,
        sendFileDrop: @escaping ([URL]) -> Void)
    {
        self.showToast = showToast
        self.sendClipboardText = sendClipboardText
        self.sendClipboardImage = sendClipboardImage
        self.sendFileDrop = sendFileDrop
    }

    public func handleLocalPasteboard(
        _ content: MBPasteboardContent,
        settings: MBCompatibilitySettings)
    {
        guard settings.shareClipboard else { return }

        switch content {
        case .text(let text):
            self.sendClipboardText(text)
            self.showToast("已同步剪贴板文本", "doc.on.clipboard")
        case .image(let data):
            self.sendClipboardImage(data)
            self.showToast("已同步剪贴板图片", "photo")
        case .files(let urls):
            guard settings.transferFiles else { return }
            self.sendFileDrop(urls)
            self.showToast("已同步剪贴板文件", "tray.and.arrow.up")
        }
    }

    public func handleTransportEvent(_ event: MBTransportEvent, settings: MBCompatibilitySettings) -> Bool {
        switch event {
        case .clipboardText(let text):
            guard settings.shareClipboard else { return true }
            MBInputManager.shared.ignoreNextClipboardChange()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            self.showToast("收到剪贴板文本", "doc.on.clipboard")
            return true
        case .clipboardImage(let data):
            guard settings.shareClipboard else { return true }
            MBInputManager.shared.ignoreNextClipboardChange()
            if let image = NSImage(data: data) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                self.showToast("收到剪贴板图片", "photo")
            }
            return true
        case .clipboardFiles(let urls):
            guard settings.shareClipboard, settings.transferFiles else { return true }
            MBInputManager.shared.ignoreNextClipboardChange()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(urls as [NSURL])
            self.dragDropFileSummary = self.makeFileSummary(urls)
            self.dragDropProgress = 1.0
            self.showToast("收到剪贴板文件", "tray.and.arrow.down")
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1500000000)
                self?.clearPresentation()
            }
            return true
        case .dragDropStateChanged(let state, let sourceName):
            guard settings.transferFiles else { return true }
            self.dragDropState = state
            self.dragDropSourceName = sourceName
            if state == nil {
                self.dragDropFileSummary = nil
                self.dragDropProgress = nil
            } else {
                self.dragDropProgress = nil
            }
            return true
        default:
            return false
        }
    }

    private func clearPresentation() {
        self.dragDropState = nil
        self.dragDropSourceName = nil
        self.dragDropFileSummary = nil
        self.dragDropProgress = nil
    }

    private func makeFileSummary(_ urls: [URL]) -> String? {
        guard !urls.isEmpty else { return nil }
        if urls.count == 1 {
            return urls[0].lastPathComponent
        }
        return "\(urls[0].lastPathComponent) +\(urls.count - 1)"
    }
}
