import MagicBorderKit

extension MBToastEvent {
    var localizedMessage: String {
        switch self {
        case .switchedToMachine(let name):
            localizedString("Switched to %@", arguments: [name])
        case .returnedToLocal:
            localizedString("Returned to local machine")
        case .switchingToMachine(let name):
            localizedString("Switching to %@...", arguments: [name])
        case .connecting(let host):
            localizedString("Connecting to %@...", arguments: [host])
        case .disconnected(let name):
            localizedString("Disconnected from %@", arguments: [name])
        case .reconnecting(let host):
            localizedString("Reconnecting to %@...", arguments: [host])
        case .reconnectStopped(let host):
            localizedString("Stopped reconnecting to %@", arguments: [host])
        case .cursorLocked:
            localizedString("Cursor locked to current screen")
        case .cursorUnlocked:
            localizedString("Cursor unlocked")
        case .inputPaused:
            localizedString("Input sharing paused")
        case .inputResumed:
            localizedString("Input sharing resumed")
        case .clipboardSyncedText:
            localizedString("Synced clipboard text")
        case .clipboardSyncedImage:
            localizedString("Synced clipboard image")
        case .clipboardSyncedFiles:
            localizedString("Synced clipboard files")
        case .clipboardReceivedText:
            localizedString("Received clipboard text")
        case .clipboardReceivedImage:
            localizedString("Received clipboard image")
        case .clipboardReceivedFiles:
            localizedString("Received clipboard files")
        case .clipboardTooLarge(let limitMB):
            localizedString("Clipboard item exceeded %d MB limit", arguments: [limitMB])
        case .clipboardEmpty:
            localizedString("Clipboard is empty or protected")
        case .fileTransferDisabled:
            localizedString("File transfer is disabled")
        case .filesSent(let summary):
            localizedString("Sent %@", arguments: [summary])
        }
    }
}

extension MBCompatibilitySettings.KeyValidationStatus {
    var localizedMessage: String {
        switch self {
        case .valid:
            localizedString("Security key is valid")
        case .tooShort:
            localizedString("Security key must be at least 16 characters")
        }
    }
}
