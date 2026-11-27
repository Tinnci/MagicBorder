public import Foundation
public import Observation

/// A bookmarked remote peer host for one-click reconnection across multi-PC setups.
public struct SavedHost: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var address: String
    public var protocolMode: MBProtocolMode
    public var messagePort: UInt16
    public var clipboardPort: UInt16
    public var autoConnect: Bool
    public var lastConnectedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        address: String,
        protocolMode: MBProtocolMode = .mwbCompatibility,
        messagePort: UInt16 = 15101,
        clipboardPort: UInt16 = 15100,
        autoConnect: Bool = false,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.protocolMode = protocolMode
        self.messagePort = messagePort
        self.clipboardPort = clipboardPort
        self.autoConnect = autoConnect
        self.lastConnectedAt = lastConnectedAt
    }
}

/// Persists bookmarked hosts in `UserDefaults` so users can switch between multiple Windows/Mac peers.
@MainActor
@Observable
public final class MBSavedHostStore {
    private static let storageKey = "network.savedHosts"

    private let defaults: UserDefaults
    public private(set) var hosts: [SavedHost] = []

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.load()
    }

    public func upsert(_ host: SavedHost) {
        if let index = self.hosts.firstIndex(where: {
            $0.id == host.id || ($0.address == host.address && $0.protocolMode == host.protocolMode)
        }) {
            self.hosts[index] = host
        } else {
            self.hosts.insert(host, at: 0)
        }
        self.save()
    }

    public func recordConnection(
        address: String,
        name: String? = nil,
        protocolMode: MBProtocolMode,
        messagePort: UInt16,
        clipboardPort: UInt16
    ) {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return }

        let existing = self.hosts.first(where: {
            $0.address == trimmedAddress && $0.protocolMode == protocolMode
        })
        let resolvedName =
            name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? existing?.name
            ?? trimmedAddress

        let entry = SavedHost(
            id: existing?.id ?? UUID(),
            name: resolvedName,
            address: trimmedAddress,
            protocolMode: protocolMode,
            messagePort: messagePort,
            clipboardPort: clipboardPort,
            autoConnect: existing?.autoConnect ?? false,
            lastConnectedAt: Date())
        self.upsert(entry)
    }

    public func remove(id: UUID) {
        self.hosts.removeAll { $0.id == id }
        self.save()
    }

    private func load() {
        guard let data = self.defaults.data(forKey: Self.storageKey),
            let decoded = try? JSONDecoder().decode([SavedHost].self, from: data)
        else { return }
        self.hosts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(self.hosts) else { return }
        self.defaults.set(data, forKey: Self.storageKey)
    }
}

extension String {
    fileprivate var nonEmpty: String? {
        self.isEmpty ? nil : self
    }
}
