import Foundation
@testable import MagicBorderKit
import XCTest

@MainActor
final class ClipboardBridgeTests: XCTestCase {
    func testLocalPasteboardDoesNotSendTextWhenClipboardSharingIsDisabled() {
        let settings = MBCompatibilitySettings()
        let originalShareClipboard = settings.shareClipboard
        defer { settings.shareClipboard = originalShareClipboard }
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
        let settings = MBCompatibilitySettings()
        let originalShareClipboard = settings.shareClipboard
        let originalTransferFiles = settings.transferFiles
        defer {
            settings.shareClipboard = originalShareClipboard
            settings.transferFiles = originalTransferFiles
        }
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
}
