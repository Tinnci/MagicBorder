import AppKit
@testable import MagicBorderKit
import XCTest

@MainActor
final class ClipboardBridgeTests: XCTestCase {
    func testLocalPasteboardDoesNotSendTextWhenClipboardSharingIsDisabled() {
        let (settings, cleanup) = self.makeSettings()
        defer { cleanup() }
        settings.shareClipboard = false
        var sentText: String?
        let bridge = MBClipboardBridge(
            showToast: { _, _ in },
            sendClipboardText: { sentText = $0 },
            sendClipboardImage: { _ in },
            sendFileDrop: { _ in })

        bridge.handleLocalPasteboard(.text("hello"), settings: settings)

        XCTAssertNil(sentText)
    }

    func testLocalPasteboardDoesNotSendFilesWhenFileTransferIsDisabled() {
        let (settings, cleanup) = self.makeSettings()
        defer { cleanup() }
        settings.shareClipboard = true
        settings.transferFiles = false
        var sentFiles: [URL] = []
        let bridge = MBClipboardBridge(
            showToast: { _, _ in },
            sendClipboardText: { _ in },
            sendClipboardImage: { _ in },
            sendFileDrop: { sentFiles = $0 })

        bridge.handleLocalPasteboard(.files([URL(fileURLWithPath: "/tmp/example.txt")]), settings: settings)

        XCTAssertTrue(sentFiles.isEmpty)
    }

    func testIncomingClipboardTextWritesPasteboardAndShowsToast() {
        let (settings, cleanup) = self.makeSettings()
        defer { cleanup() }
        settings.shareClipboard = true
        var toasts: [(String, String)] = []
        let bridge = self.makeBridge(showToast: { toasts.append(($0, $1)) })

        let handled = bridge.handleTransportEvent(.clipboardText("hello"), settings: settings)

        XCTAssertTrue(handled)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello")
        XCTAssertEqual(toasts.last?.0, "收到剪贴板文本")
    }

    func testIncomingClipboardImageShowsToastWhenSharingIsEnabled() {
        let (settings, cleanup) = self.makeSettings()
        defer { cleanup() }
        settings.shareClipboard = true
        var toasts: [(String, String)] = []
        let bridge = self.makeBridge(showToast: { toasts.append(($0, $1)) })

        let handled = bridge.handleTransportEvent(
            .clipboardImage(self.onePixelPNGData()),
            settings: settings)

        XCTAssertTrue(handled)
        XCTAssertEqual(toasts.last?.0, "收到剪贴板图片")
    }

    func testIncomingClipboardFilesUpdatePresentationWhenTransfersAreEnabled() {
        let (settings, cleanup) = self.makeSettings()
        defer { cleanup() }
        settings.shareClipboard = true
        settings.transferFiles = true
        var toasts: [(String, String)] = []
        let bridge = self.makeBridge(showToast: { toasts.append(($0, $1)) })
        let urls = [
            URL(fileURLWithPath: "/tmp/one.txt"),
            URL(fileURLWithPath: "/tmp/two.txt"),
        ]

        let handled = bridge.handleTransportEvent(.clipboardFiles(urls), settings: settings)

        XCTAssertTrue(handled)
        XCTAssertEqual(bridge.dragDropFileSummary, "one.txt +1")
        XCTAssertEqual(bridge.dragDropProgress, 1.0)
        XCTAssertEqual(toasts.last?.0, "收到剪贴板文件")
    }

    func testIncomingClipboardTextIsConsumedWhenSharingIsDisabled() {
        let (settings, cleanup) = self.makeSettings()
        defer { cleanup() }
        settings.shareClipboard = false
        var toasts: [(String, String)] = []
        let bridge = self.makeBridge(showToast: { toasts.append(($0, $1)) })

        let handled = bridge.handleTransportEvent(.clipboardText("blocked"), settings: settings)

        XCTAssertTrue(handled)
        XCTAssertTrue(toasts.isEmpty)
    }

    func testDragDropStateIsConsumedWhenFileTransferIsDisabled() {
        let (settings, cleanup) = self.makeSettings()
        defer { cleanup() }
        settings.transferFiles = false
        let bridge = self.makeBridge()

        let handled = bridge.handleTransportEvent(
            .dragDropStateChanged(.dragging, sourceName: "Windows"),
            settings: settings)

        XCTAssertTrue(handled)
        XCTAssertNil(bridge.dragDropState)
        XCTAssertNil(bridge.dragDropSourceName)
    }

    func testDragDropEndClearsPresentation() {
        let (settings, cleanup) = self.makeSettings()
        defer { cleanup() }
        settings.transferFiles = true
        let bridge = self.makeBridge()

        _ = bridge.handleTransportEvent(
            .dragDropStateChanged(.dragging, sourceName: "Windows"),
            settings: settings)
        _ = bridge.handleTransportEvent(.dragDropStateChanged(nil, sourceName: nil), settings: settings)

        XCTAssertNil(bridge.dragDropState)
        XCTAssertNil(bridge.dragDropSourceName)
        XCTAssertNil(bridge.dragDropFileSummary)
        XCTAssertNil(bridge.dragDropProgress)
    }

    private func makeBridge(showToast: @escaping (String, String) -> Void = { _, _ in })
        -> MBClipboardBridge
    {
        MBClipboardBridge(
            showToast: showToast,
            sendClipboardText: { _ in },
            sendClipboardImage: { _ in },
            sendFileDrop: { _ in })
    }

    private func makeSettings() -> (MBCompatibilitySettings, () -> Void) {
        let suiteName = "MagicBorderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (
            MBCompatibilitySettings(defaults: defaults),
            { defaults.removePersistentDomain(forName: suiteName) })
    }

    private func onePixelPNGData() -> Data {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Could not create test PNG")
            return Data()
        }
        return png
    }
}
