import AppKit
public import Foundation

public enum MBPasteboardContent: Equatable, Sendable {
    case text(String)
    case image(Data)
    case files([URL])
}

@MainActor
public final class MBPasteboardMonitor {
    private let pasteboard: any PasteboardAccessing
    private var lastChangeCount: Int
    private var ignoredChangeCount: Int?
    private let pollingTask = CancellableTaskSlot()
    private let imageConversionTask = CancellableTaskSlot()

    public var onChange: ((MBPasteboardContent) -> Void)?

    public init(pasteboard: any PasteboardAccessing = SystemPasteboard()) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    deinit {
        self.pollingTask.cancel()
        self.imageConversionTask.cancel()
    }

    public func startPolling(interval: Duration = .milliseconds(500)) {
        guard !self.pollingTask.isActive else { return }
        let task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { break }
                self.checkForChanges()
            }
        }
        self.pollingTask.replace(with: task)
    }

    public func stopPolling() {
        self.pollingTask.cancel()
        self.imageConversionTask.cancel()
    }

    public func ignoreNextChange() {
        self.ignoredChangeCount = self.pasteboard.changeCount + 1
    }

    public func checkForChanges() {
        let count = self.pasteboard.changeCount
        guard count != self.lastChangeCount else { return }
        self.lastChangeCount = count

        if let ignored = self.ignoredChangeCount, ignored == count {
            self.ignoredChangeCount = nil
            return
        }

        if let items = self.pasteboard.readFileURLs(), !items.isEmpty {
            self.onChange?(.files(items))
            return
        }

        if let string = self.pasteboard.readString(), !string.isEmpty {
            self.onChange?(.text(string))
            return
        }

        if let pngData = self.pasteboard.readPNGData(), !pngData.isEmpty {
            self.onChange?(.image(pngData))
            return
        }

        if let tiffData = self.pasteboard.readImageTIFFData(), !tiffData.isEmpty {
            let task = Task { @MainActor [weak self] in
                let png = await Task.detached(priority: .utility) {
                    Self.convertTIFFToPNG(tiffData)
                }.value
                guard !Task.isCancelled, let png else { return }
                self?.onChange?(.image(png))
            }
            self.imageConversionTask.replace(with: task)
        }
    }

    private nonisolated static func convertTIFFToPNG(_ tiffData: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
