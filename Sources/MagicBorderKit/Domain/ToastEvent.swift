/// Typed domain events for user-facing toast notifications.
///
/// `MagicBorderKit` emits semantic events rather than localized UI strings so the
/// presentation target owns localization and formatting.
public enum MBToastEvent: Equatable, Sendable {
    case switchedToMachine(String)
    case returnedToLocal
    case switchingToMachine(String)
    case connecting(String)
    case connected(String)
    case disconnected(String)
    case noConnectedDevices
    case reconnecting(String)
    case reconnectStopped(String)
    case cursorLocked
    case cursorUnlocked
    case inputPaused
    case inputResumed
    case lockedAllScreens
    case clipboardSyncedText
    case clipboardSyncedImage
    case clipboardSyncedFiles
    case clipboardReceivedText
    case clipboardReceivedImage
    case clipboardReceivedFiles
    case clipboardTooLarge(Int)
    case clipboardEmpty
    case fileTransferDisabled
    case filesSent(String)

    public var defaultSystemImage: String {
        switch self {
        case .switchedToMachine:
            "arrow.right"
        case .returnedToLocal:
            "arrow.left"
        case .switchingToMachine:
            "arrow.triangle.2.circlepath"
        case .connecting:
            "arrow.right.circle"
        case .connected:
            "link"
        case .disconnected, .noConnectedDevices:
            "link.slash"
        case .reconnecting:
            "arrow.clockwise"
        case .reconnectStopped:
            "pause.circle"
        case .cursorLocked:
            "lock.display"
        case .cursorUnlocked:
            "lock.open.display"
        case .inputPaused:
            "pause.circle.fill"
        case .inputResumed:
            "play.circle.fill"
        case .lockedAllScreens:
            "lock.shield.fill"
        case .clipboardSyncedText, .clipboardReceivedText:
            "doc.on.clipboard"
        case .clipboardSyncedImage, .clipboardReceivedImage:
            "photo"
        case .clipboardSyncedFiles, .filesSent:
            "tray.and.arrow.up"
        case .clipboardReceivedFiles:
            "tray.and.arrow.down"
        case .clipboardTooLarge, .clipboardEmpty:
            "exclamationmark.triangle"
        case .fileTransferDisabled:
            "nosign"
        }
    }
}
