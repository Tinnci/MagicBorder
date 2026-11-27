/// `MBInputRoutingDelegate` breaks the circular dependency between
/// `MBInputManager` and `MBNetworkManager`.
@MainActor
public protocol MBInputRoutingDelegate: AnyObject {
    /// Forward an intercepted local input event to the active remote machine.
    func sendRemoteInput(snapshot: EventSnapshot)

    /// Notify that the cursor moved locally (may trigger an edge switch).
    func handleLocalMouseEvent(snapshot: EventSnapshot)

    /// Notify that the cursor moved while in remote mode (edge-release / neighbor switch check).
    func handleRemoteMouseEvent(snapshot: EventSnapshot)

    /// Forward a local clipboard change to the active remote machine.
    func handleLocalPasteboard(_ content: MBPasteboardContent)

    /// Return control to the local machine immediately (e.g. user pressed Escape).
    func forceReturnToLocal(reason: String)
}
