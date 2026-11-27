import Foundation
import Observation

enum MBOverlayPosition: String, CaseIterable, Codable, Sendable {
    case top
    case topLeading
    case topTrailing
    case bottom
    case bottomLeading
    case bottomTrailing
}

struct MBOverlayPreferences: Codable, Equatable, Sendable {
    var showDevice: Bool
    var showProgress: Bool
    var scale: Double
    var position: MBOverlayPosition
}

@MainActor
@Observable
final class MBOverlayPreferencesStore {
    private enum Keys {
        static let overrides = "overlay.preferences.overrides"
    }

    private let defaults = UserDefaults.standard
    private(set) var overrides: [String: MBOverlayPreferences] = [:]

    init() {
        self.load()
    }

    func preferences(for deviceName: String, default defaultPreferences: MBOverlayPreferences) -> MBOverlayPreferences {
        self.overrides[deviceName] ?? defaultPreferences
    }

    func setOverride(_ preferences: MBOverlayPreferences, for deviceName: String) {
        self.overrides[deviceName] = preferences
        self.save()
    }

    func clearOverride(for deviceName: String) {
        self.overrides.removeValue(forKey: deviceName)
        self.save()
    }

    func hasOverride(for deviceName: String) -> Bool {
        self.overrides[deviceName] != nil
    }

    func allDeviceNames() -> [String] {
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
