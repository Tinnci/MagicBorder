import Foundation
import Observation

public enum MBOverlayPosition: String, CaseIterable, Codable, Sendable {
    case top
    case topLeading
    case topTrailing
    case bottom
    case bottomLeading
    case bottomTrailing
}

public struct MBOverlayPreferences: Codable, Equatable, Sendable {
    public var showDevice: Bool
    public var showProgress: Bool
    public var scale: Double
    public var position: MBOverlayPosition

    public init(showDevice: Bool, showProgress: Bool, scale: Double, position: MBOverlayPosition) {
        self.showDevice = showDevice
        self.showProgress = showProgress
        self.scale = scale
        self.position = position
    }
}

@MainActor
@Observable
public final class MBOverlayPreferencesStore {
    private enum Keys {
        static let overrides = "overlay.preferences.overrides"
    }

    private let defaults = UserDefaults.standard
    public private(set) var overrides: [String: MBOverlayPreferences] = [:]

    public init() {
        self.load()
    }

    public func preferences(for deviceName: String, default defaultPreferences: MBOverlayPreferences) -> MBOverlayPreferences {
        self.overrides[deviceName] ?? defaultPreferences
    }

    public func setOverride(_ preferences: MBOverlayPreferences, for deviceName: String) {
        self.overrides[deviceName] = preferences
        self.save()
    }

    public func clearOverride(for deviceName: String) {
        self.overrides.removeValue(forKey: deviceName)
        self.save()
    }

    public func hasOverride(for deviceName: String) -> Bool {
        self.overrides[deviceName] != nil
    }

    public func allDeviceNames() -> [String] {
        self.overrides.keys.sorted()
    }

    private func load() {
        guard let data = defaults.data(forKey: Keys.overrides) else { return }
        if let decoded = try? JSONDecoder().decode([String: MBOverlayPreferences].self, from: data) {
            self.overrides = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        self.defaults.set(data, forKey: Keys.overrides)
    }
}
