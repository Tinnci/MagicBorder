/// `MBInputRoutingDelegate` is the seam that breaks the circular dependency between
/// `MBInputManager` and `MBNetworkManager`.
///
/// `MBInputManager` calls through this protocol instead of referencing
/// `MBNetworkManager.shared` directly. `MBNetworkManager` adopts this protocol
/// and injects itself during `init()`.
///
/// Dependency graph (post-fix):
/// ```
/// MBNetworkManager ──owns──► MBInputManager   (one-way: NM sets remote target, simulates events)
/// MBInputManager   ──uses──► MBInputRoutingDelegate   (protocol: send input, edge detection)
///                                 ▲
///                        MBNetworkManager conforms
/// ```
@MainActor
public protocol MBInputRoutingDelegate: AnyObject {
    /// Forward an intercepted local input event to the active remote machine.
    func sendRemoteInput(snapshot: EventSnapshot)

    /// Notify that the cursor hit a local screen edge (may trigger a machine switch).
    func handleLocalMouseEvent(snapshot: EventSnapshot)

    /// Notify that the cursor moved while already in remote mode (edge-release check).
    func handleRemoteMouseEvent(snapshot: EventSnapshot)

    /// Forward a local clipboard change to the active remote machine.
    func handleLocalPasteboard(_ content: MBPasteboardContent)

    /// Return control to the local machine immediately (e.g. user pressed Escape).
    func forceReturnToLocal(reason: String)

    /// Read-only access to compatibility settings needed for cursor-warping decisions.
    var compatibilitySettings: MBCompatibilitySettings { get }
}
