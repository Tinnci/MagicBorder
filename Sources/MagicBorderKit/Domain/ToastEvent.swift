/// Typed domain events for user-facing toast notifications.
///
/// `MagicBorderKit` emits semantic events rather than localized UI strings so the
/// presentation target owns localization and formatting.
public enum MBToastEvent: Equatable, Sendable {
    case switchedToMachine(String)
    case returnedToLocal
    case switchingToMachine(String)
    case connecting(String)
    case disconnected(String)
    case reconnecting(String)
    case reconnectStopped(String)
    case clipboardSyncedText
    case clipboardSyncedImage
    case clipboardSyncedFiles
    case clipboardReceivedText
    case clipboardReceivedImage
    case clipboardReceivedFiles
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
        case .disconnected:
            "link.slash"
        case .reconnecting:
            "arrow.clockwise"
        case .reconnectStopped:
            "pause.circle"
        case .clipboardSyncedText, .clipboardReceivedText:
            "doc.on.clipboard"
        case .clipboardSyncedImage, .clipboardReceivedImage:
            "photo"
        case .clipboardSyncedFiles, .filesSent:
            "tray.and.arrow.up"
        case .clipboardReceivedFiles:
            "tray.and.arrow.down"
        case .fileTransferDisabled:
            "nosign"
        }
    }
}
