import AppKit
import Observation
import TowerCore
import UserNotifications

/// Polls Tower while the Mac is awake and holds what the menu shows.
@MainActor @Observable
final class TowerStore {
    /// Never poll faster than this, even on "Refresh now".
    static let minGap: TimeInterval = 2

    let settings: Settings
    private(set) var state: PollState
    /// Time of the last render input; advanced with every poll.
    private(set) var now = Date()

    private let client = TowerClient()
    private var loop: Task<Void, Never>?
    private var lastFetch: Date?
    private var generation = 0

    var presentation: Presentation { Presentation(state: state, now: now) }

    init(settings: Settings) {
        self.settings = settings
        state = PollState(hasAddress: settings.address != nil)
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        }
        restart()
    }

    /// Polls now (respecting the 2 s floor), then every `pollInterval` seconds.
    func restart() {
        stop()
        generation += 1
        let gen = generation
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let last = self.lastFetch {
                    let wait = Self.minGap - Date().timeIntervalSince(last)
                    if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                }
                guard !Task.isCancelled, gen == self.generation else { return }
                await self.poll(generation: gen)
                try? await Task.sleep(for: .seconds(self.settings.pollInterval))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Called after the address changes: forget the old Tower's data.
    func addressChanged() {
        state = state.reset(hasAddress: settings.address != nil)
        lastFetch = nil
        now = Date()
        restart()
    }

    private func poll(generation gen: Int) async {
        guard let address = settings.address else {
            state.hasAddress = false
            now = Date()
            return
        }
        lastFetch = Date()
        let outcome = await client.fetch(address)
        guard gen == generation else { return }  // address changed mid-flight
        let before = state.lastGood?.needsYou.count
        state = state.applying(outcome, at: Date())
        now = Date()
        if case .snapshot(let s) = outcome, let before, s.needsYou.count > before {
            notifyNeedsYou(count: s.needsYou.count, added: s.needsYou.count - before)
        }
    }

    // MARK: - Notifications

    private func notifyNeedsYou(count: Int, added: Int) {
        guard settings.notifyNeedsYou, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tower needs you"
        content.body = added == 1 ? "1 new item · \(count) waiting" : "\(added) new items · \(count) waiting"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
