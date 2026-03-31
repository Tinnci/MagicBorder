import Foundation

/// A peer machine discovered or connected on the network.
/// This is the canonical domain model — the single source of truth for a remote peer.
/// Previously fragmented across: `Machine` (UI layer), `ConnectedMachine` (NetworkManager),
/// `MachineInfo` (wire DTO), and `MWBPeer` (MWB compat layer).
public struct Machine: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var isOnline: Bool

    public init(id: UUID, name: String, isOnline: Bool) {
        self.id = id
        self.name = name
        self.isOnline = isOnline
    }
}
