import Foundation
import Observation
import TowerCore

/// User settings, kept in `UserDefaults`. The app holds no secrets.
@MainActor @Observable
final class Settings {
    static let intervalRange = 5...60
    static let defaultInterval = 10

    private enum Key {
        static let address = "towerAddress"
        static let interval = "pollIntervalSeconds"
        static let notify = "notifyNeedsYou"
    }

    private let defaults: UserDefaults

    /// As typed; empty means not set.
    var addressText: String { didSet { defaults.set(addressText, forKey: Key.address) } }
    var pollInterval: Int { didSet { defaults.set(pollInterval, forKey: Key.interval) } }
    /// macOS notification when the needs-you count goes up. Off by default.
    var notifyNeedsYou: Bool { didSet { defaults.set(notifyNeedsYou, forKey: Key.notify) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        addressText = defaults.string(forKey: Key.address) ?? ""
        let stored = defaults.integer(forKey: Key.interval)
        pollInterval = stored == 0 ? Self.defaultInterval : Self.clamp(stored)
        notifyNeedsYou = defaults.bool(forKey: Key.notify)
    }

    var address: TowerAddress? { TowerAddress(addressText) }

    static func clamp(_ seconds: Int) -> Int {
        min(max(seconds, intervalRange.lowerBound), intervalRange.upperBound)
    }
}
