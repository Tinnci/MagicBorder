import AppKit
import Foundation

public enum MBPasteboardContent: Equatable {
    case text(String)
    case image(Data)
    case files([URL])
}

@MainActor
public final class MBPasteboardMonitor {
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var ignoredChangeCount: Int?

    public var onChange: ((MBPasteboardContent) -> Void)?

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    public func startPolling(interval: UInt64 = 500_000_000) {
        Task { @MainActor in
            while true {
                try? await Task.sleep(nanoseconds: interval)
                self.checkForChanges()
            }
        }
    }

    public func ignoreNextChange() {
        ignoredChangeCount = pasteboard.changeCount + 1
    }

    private func checkForChanges() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if let ignored = ignoredChangeCount, ignored == count {
            ignoredChangeCount = nil
            return
        }

        if let items = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !items.isEmpty {
            onChange?(.files(items))
            return
        }

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            onChange?(.text(string))
            return
        }

        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            onChange?(.image(png))
        }
    }
}
