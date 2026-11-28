import AppKit
import Foundation
import Testing

@testable import MagicBorderKit

@Suite("SystemSymbolAudit")
struct SystemSymbolAuditTests {
    @Test func toastEventDefaultSystemImagesExistOnMacOS() {
        let samples: [MBToastEvent] = [
            .switchedToMachine("WinPC"),
            .returnedToLocal,
            .switchingToMachine("WinPC"),
            .connecting("192.168.1.5"),
            .connected("WinPC"),
            .disconnected("WinPC"),
            .noConnectedDevices,
            .reconnecting("192.168.1.5"),
            .reconnectStopped("192.168.1.5"),
            .cursorLocked,
            .cursorUnlocked,
            .inputPaused,
            .inputResumed,
            .lockedAllScreens,
            .clipboardSyncedText,
            .clipboardSyncedImage,
            .clipboardSyncedFiles,
            .clipboardReceivedText,
            .clipboardReceivedImage,
            .clipboardReceivedFiles,
            .clipboardTooLarge(10),
            .clipboardEmpty,
            .fileTransferDisabled,
            .filesSent("demo.zip"),
        ]

        for event in samples {
            let symbolName = event.defaultSystemImage
            #expect(
                NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil,
                "Missing SF Symbol '\(symbolName)' for MBToastEvent.\(event)")
        }
    }

    @Test func allSourceSFSystemSymbolsResolveOnMacOS() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesDir = packageRoot.appendingPathComponent("Sources")

        guard
            let enumerator = FileManager.default.enumerator(
                at: sourcesDir,
                includingPropertiesForKeys: nil)
        else {
            Issue.record("Failed to enumerate Sources directory at \(sourcesDir.path)")
            return
        }

        let patterns = [
            #"systemImage:\s*"([a-z0-9]+(?:\.[a-z0-9]+)+)""#,
            #"systemName:\s*"([a-z0-9]+(?:\.[a-z0-9]+)+)""#,
            #"systemSymbolName:\s*"([a-z0-9]+(?:\.[a-z0-9]+)+)""#,
            #"symbolImage\(named:\s*"([a-z0-9]+(?:\.[a-z0-9]+)+)""#,
        ]
        let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }

        var checkedSymbols: Set<String> = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            for regex in regexes {
                for match in regex.matches(in: content, range: range) {
                    guard match.numberOfRanges > 1,
                        let symbolRange = Range(match.range(at: 1), in: content)
                    else { continue }
                    let symbolName = String(content[symbolRange])
                    checkedSymbols.insert(symbolName)
                    #expect(
                        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil,
                        "Invalid SF Symbol '\(symbolName)' referenced in \(fileURL.lastPathComponent)")
                }
            }
        }

        #expect(!checkedSymbols.isEmpty)
    }
}
