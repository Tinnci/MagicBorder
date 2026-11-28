import Foundation
import Testing

@testable import MagicBorderKit

@Suite("ClipboardBridge")
@MainActor
struct ClipboardBridgeTests {
    @Test func localPasteboardDoesNotSendTextWhenClipboardSharingIsDisabled() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.shareClipboard = false
        var sentText: String?
        let bridge = MBClipboardBridge(
            pasteboard: FakePasteboard(),
            emitToast: { _ in },
            sendClipboardText: { sentText = $0 },
            sendClipboardImage: { _ in },
            sendFileDrop: { _ in true })

        bridge.handleLocalPasteboard(.text("hello"), settings: settings)

        #expect(sentText == nil)
    }

    @Test func localPasteboardDoesNotSendFilesWhenFileTransferIsDisabled() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.shareClipboard = true
        settings.transferFiles = false
        var sentFiles: [URL] = []
        let bridge = MBClipboardBridge(
            pasteboard: FakePasteboard(),
            emitToast: { _ in },
            sendClipboardText: { _ in },
            sendClipboardImage: { _ in },
            sendFileDrop: {
                sentFiles = $0
                return true
            })

        bridge.handleLocalPasteboard(.files([URL(fileURLWithPath: "/tmp/example.txt")]), settings: settings)

        #expect(sentFiles.isEmpty)
    }

    @Test func disconnectedBridgeDoesNotSyncOrToastOnLocalCopy() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.shareClipboard = true
        settings.transferFiles = true
        settings.maxClipboardSizeMB = 1
        let pasteboard = FakePasteboard()
        pasteboard.storedString = "manual-when-offline"
        var sentTexts: [String] = []
        var sentImages: [Data] = []
        var sentFiles: [URL] = []
        var toasts: [MBToastEvent] = []

        let bridge = MBClipboardBridge(
            pasteboard: pasteboard,
            hasConnectedPeers: { false },
            emitToast: { toasts.append($0) },
            sendClipboardText: { sentTexts.append($0) },
            sendClipboardImage: { sentImages.append($0) },
            sendFileDrop: {
                sentFiles = $0
                return true
            })

        bridge.handleLocalPasteboard(.text("local-only"), settings: settings)
        bridge.handleLocalPasteboard(.image(Data(repeating: 0xAB, count: 2_000_000)), settings: settings)
        bridge.handleLocalPasteboard(.files([URL(fileURLWithPath: "/tmp/offline.txt")]), settings: settings)

        #expect(sentTexts.isEmpty)
        #expect(sentImages.isEmpty)
        #expect(sentFiles.isEmpty)
        #expect(toasts.isEmpty)

        bridge.pushCurrentClipboard(settings: settings)
        #expect(sentTexts.isEmpty)
        #expect(toasts == [.noConnectedDevices])
    }

    @Test func connectedBridgeSyncsAutomaticCopiesQuietlyAndManualPushShowsToast() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.shareClipboard = true
        settings.transferFiles = true
        let pasteboard = FakePasteboard()
        pasteboard.storedString = "manual-sync"
        var sentTexts: [String] = []
        var toasts: [MBToastEvent] = []

        let bridge = MBClipboardBridge(
            pasteboard: pasteboard,
            hasConnectedPeers: { true },
            emitToast: { toasts.append($0) },
            sendClipboardText: { sentTexts.append($0) },
            sendClipboardImage: { _ in },
            sendFileDrop: { _ in false })

        bridge.handleLocalPasteboard(.text("background-copy"), settings: settings)
        #expect(sentTexts == ["background-copy"])
        #expect(toasts.isEmpty)

        bridge.handleLocalPasteboard(
            .files([URL(fileURLWithPath: "/tmp/blocked.txt")]),
            settings: settings,
            isManual: true)
        #expect(toasts.isEmpty)

        bridge.pushCurrentClipboard(settings: settings)
        #expect(sentTexts == ["background-copy", "manual-sync"])
        #expect(toasts == [.clipboardSyncedText])
    }

    @Test func incomingClipboardTextWritesInjectedPasteboardAndEmitsToast() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.shareClipboard = true
        let pasteboard = FakePasteboard()
        var ignoredCount = 0
        var toasts: [MBToastEvent] = []
        let bridge = MBClipboardBridge(
            pasteboard: pasteboard,
            ignoreNextLocalChange: { ignoredCount += 1 },
            emitToast: { toasts.append($0) },
            sendClipboardText: { _ in },
            sendClipboardImage: { _ in },
            sendFileDrop: { _ in true })

        let handled = bridge.handleTransportEvent(.clipboardText("hello"), settings: settings)

        #expect(handled)
        #expect(ignoredCount == 1)
        #expect(pasteboard.storedString == "hello")
        #expect(toasts.last == .clipboardReceivedText)
    }

    @Test func incomingClipboardImageEmitsToastWhenImageWriteSucceeds() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.shareClipboard = true
        let pasteboard = FakePasteboard()
        var toasts: [MBToastEvent] = []
        let bridge = MBClipboardBridge(
            pasteboard: pasteboard,
            emitToast: { toasts.append($0) },
            sendClipboardText: { _ in },
            sendClipboardImage: { _ in },
            sendFileDrop: { _ in true })

        let handled = bridge.handleTransportEvent(.clipboardImage(Data([1, 2, 3, 4])), settings: settings)

        #expect(handled)
        #expect(pasteboard.storedPNGData == Data([1, 2, 3, 4]))
        #expect(toasts.last == .clipboardReceivedImage)
    }

    @Test func incomingClipboardFilesUpdatePresentationWhenTransfersAreEnabled() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.shareClipboard = true
        settings.transferFiles = true
        let pasteboard = FakePasteboard()
        var toasts: [MBToastEvent] = []
        let bridge = MBClipboardBridge(
            pasteboard: pasteboard,
            emitToast: { toasts.append($0) },
            sendClipboardText: { _ in },
            sendClipboardImage: { _ in },
            sendFileDrop: { _ in true })
        let urls = [
            URL(fileURLWithPath: "/tmp/one.txt"),
            URL(fileURLWithPath: "/tmp/two.txt"),
        ]

        let handled = bridge.handleTransportEvent(.clipboardFiles(urls), settings: settings)

        #expect(handled)
        #expect(pasteboard.storedFileURLs == urls)
        #expect(bridge.dragDropFileSummary == "one.txt +1")
        #expect(bridge.dragDropProgress == 1.0)
        #expect(toasts.last == .clipboardReceivedFiles)
    }

    @Test func incomingClipboardTextIsConsumedWhenSharingIsDisabled() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.shareClipboard = false
        let pasteboard = FakePasteboard()
        var toasts: [MBToastEvent] = []
        let bridge = MBClipboardBridge(
            pasteboard: pasteboard,
            emitToast: { toasts.append($0) },
            sendClipboardText: { _ in },
            sendClipboardImage: { _ in },
            sendFileDrop: { _ in true })

        let handled = bridge.handleTransportEvent(.clipboardText("blocked"), settings: settings)

        #expect(handled)
        #expect(pasteboard.storedString == nil)
        #expect(toasts.isEmpty)
    }

    @Test func dragDropEndClearsPresentation() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = MBCompatibilitySettings(defaults: defaults)
        settings.transferFiles = true
        let bridge = MBClipboardBridge(
            pasteboard: FakePasteboard(),
            emitToast: { _ in },
            sendClipboardText: { _ in },
            sendClipboardImage: { _ in },
            sendFileDrop: { _ in true })

        _ = bridge.handleTransportEvent(.dragDropStateChanged(.dragging, sourceName: "Windows"), settings: settings)
        #expect(bridge.dragDropState == .dragging)
        #expect(bridge.dragDropSourceName == "Windows")

        _ = bridge.handleTransportEvent(.dragDropStateChanged(nil, sourceName: nil), settings: settings)
        #expect(bridge.dragDropState == nil)
        #expect(bridge.dragDropSourceName == nil)
        #expect(bridge.dragDropFileSummary == nil)
        #expect(bridge.dragDropProgress == nil)
    }
}
