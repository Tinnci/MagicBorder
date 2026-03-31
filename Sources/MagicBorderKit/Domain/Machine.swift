import CoreGraphics
import Foundation

/// Connection lifecycle of a machine in the network.
public enum MachineConnectionState: String, Codable, Equatable, Sendable {
    case local // the machine running this app
    case discovered // visible on the network, not yet connected
    case connecting // TCP/handshake in progress
    case connected // handshake complete, ready to forward input
    case active // currently receiving input (local cursor → this machine)
}

/// A machine participating in the MagicBorder session.
///
/// This is the canonical aggregate root for any network peer (and for the local machine
/// when it appears in the arrangement view). Previously fragmented across `Machine` (UI layer),
/// `ConnectedMachine` (nested in NetworkManager), `MachineInfo` (wire DTO), and `MWBPeer`.
public struct Machine: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var state: MachineConnectionState
    public var screenSize: CGSize

    /// MWB protocol peer ID. `nil` for local or modern-protocol machines.
    public var mwbPeerID: Int32?

    /// Convenience accessor for views — true when the machine can receive input.
    public var isOnline: Bool { self.state == .connected || self.state == .active }

    public init(
        id: UUID,
        name: String,
        state: MachineConnectionState = .discovered,
        screenSize: CGSize = .zero,
        mwbPeerID: Int32? = nil)
    {
        self.id = id
        self.name = name
        self.state = state
        self.screenSize = screenSize
        self.mwbPeerID = mwbPeerID
    }
}
