public import Foundation
public import Observation

/// Per-peer input ergonomics overriding global defaults for a specific Windows or Mac machine.
public struct PeerInputProfile: Codable, Equatable, Sendable {
    public var modifierRemapMode: MBModifierRemapMode
    public var invertRemoteScroll: Bool
    public var remoteScrollSpeed: Double

    public init(
        modifierRemapMode: MBModifierRemapMode = .standard,
        invertRemoteScroll: Bool = false,
        remoteScrollSpeed: Double = 1.0
    ) {
        self.modifierRemapMode = modifierRemapMode
        self.invertRemoteScroll = invertRemoteScroll
        self.remoteScrollSpeed = remoteScrollSpeed
    }
}

/// Persists per-peer input overrides in `UserDefaults`, keyed by uppercased machine name.
@MainActor
@Observable
public final class MBPeerProfileStore {
    private static let storageKey = "input.peerProfiles"

    private let defaults: UserDefaults
    public private(set) var overrides: [String: PeerInputProfile] = [:]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.load()
    }

    public func profile(
        for machineName: String?,
        default defaultProfile: PeerInputProfile
    ) -> PeerInputProfile {
        guard let key = Self.normalizedKey(for: machineName) else { return defaultProfile }
        return self.overrides[key] ?? defaultProfile
    }

    public func hasOverride(for machineName: String) -> Bool {
        guard let key = Self.normalizedKey(for: machineName) else { return false }
        return self.overrides[key] != nil
    }

    public func setOverride(_ profile: PeerInputProfile, for machineName: String) {
        guard let key = Self.normalizedKey(for: machineName) else { return }
        self.overrides[key] = profile
        self.save()
    }

    public func clearOverride(for machineName: String) {
        guard let key = Self.normalizedKey(for: machineName) else { return }
        self.overrides.removeValue(forKey: key)
        self.save()
    }

    private static func normalizedKey(for machineName: String?) -> String? {
        guard let trimmed = machineName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed.uppercased()
    }

    private func load() {
        guard let data = self.defaults.data(forKey: Self.storageKey),
            let decoded = try? JSONDecoder().decode([String: PeerInputProfile].self, from: data)
        else { return }
        self.overrides = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(self.overrides) else { return }
        self.defaults.set(data, forKey: Self.storageKey)
    }
}
