import AppKit
import Foundation
import Testing

@testable import MagicBorderKit

@Suite("Pasteboard Monitor")
@MainActor
struct PasteboardMonitorTests {
    @Test func checkForChangesIsNoOpWhenChangeCountUnchanged() {
        let pasteboard = FakePasteboard()
        pasteboard.storedString = "initial"
        let monitor = MBPasteboardMonitor(pasteboard: pasteboard)

        var received: [MBPasteboardContent] = []
        monitor.onChange = { received.append($0) }

        monitor.checkForChanges()

        #expect(received.isEmpty)
    }

    @Test func ignoreNextChangeSuppressesOnlyImmediateUpdate() {
        let pasteboard = FakePasteboard()
        let monitor = MBPasteboardMonitor(pasteboard: pasteboard)

        var received: [MBPasteboardContent] = []
        monitor.onChange = { received.append($0) }

        monitor.ignoreNextChange()
        pasteboard.writeString("ignored-remote-write")
        monitor.checkForChanges()
        #expect(received.isEmpty)

        pasteboard.writeString("local-copy")
        monitor.checkForChanges()
        #expect(received == [.text("local-copy")])
    }

    @Test func checkForChangesPrefersFilesThenTextThenPNG() {
        let pasteboard = FakePasteboard()
        let monitor = MBPasteboardMonitor(pasteboard: pasteboard)

        var received: [MBPasteboardContent] = []
        monitor.onChange = { received.append($0) }

        let fileURL = URL(fileURLWithPath: "/tmp/example.txt")
        pasteboard.storedFileURLs = [fileURL]
        pasteboard.storedString = "fallback-text"
        pasteboard.storedPNGData = Data([0x89, 0x50, 0x4E, 0x47])
        pasteboard.changeCount += 1
        monitor.checkForChanges()

        pasteboard.storedFileURLs = nil
        pasteboard.changeCount += 1
        monitor.checkForChanges()

        pasteboard.storedString = nil
        pasteboard.changeCount += 1
        monitor.checkForChanges()

        #expect(
            received == [
                .files([fileURL]),
                .text("fallback-text"),
                .image(Data([0x89, 0x50, 0x4E, 0x47])),
            ])
    }

    @Test func checkForChangesConvertsTIFFToPNGAsync() async throws {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 2,
                pixelsHigh: 2,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0))
        let tiffData = try #require(bitmap.tiffRepresentation)

        let pasteboard = FakePasteboard()
        let monitor = MBPasteboardMonitor(pasteboard: pasteboard)
        defer { monitor.stopPolling() }

        let convertedPNG = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            var resumed = false
            monitor.onChange = { content in
                guard !resumed else { return }
                resumed = true
                if case .image(let png) = content {
                    continuation.resume(returning: png)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            pasteboard.storedTIFFData = tiffData
            pasteboard.changeCount += 1
            monitor.checkForChanges()
        }

        let png = try #require(convertedPNG)
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func pollingStartsIdempotentlyAndStopsCleanly() async {
        let pasteboard = FakePasteboard()
        let monitor = MBPasteboardMonitor(pasteboard: pasteboard)
        defer { monitor.stopPolling() }

        var events: [MBPasteboardContent] = []
        monitor.onChange = { events.append($0) }

        monitor.startPolling(interval: .milliseconds(15))
        monitor.startPolling(interval: .milliseconds(15))
        pasteboard.writeString("polled-text")

        for _ in 0..<40 where events.isEmpty {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(events == [.text("polled-text")])

        monitor.stopPolling()
        pasteboard.writeString("after-stop")
        try? await Task.sleep(for: .milliseconds(60))
        #expect(events == [.text("polled-text")])
    }
}
