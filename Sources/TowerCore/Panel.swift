import Foundation

/// Structured view of a snapshot for the popover panel. Same rules as
/// `Presentation` (spec section 4), but as fields instead of text lines.
public struct Panel: Sendable, Equatable {
    public enum AgentTone: Sendable, Equatable { case working, waiting, blocked, idle }

    public struct Slots: Sendable, Equatable {
        public var occupied: Int?
        public var allocated: Int?
        public var overbooked: Bool { (occupied ?? 0) > (allocated ?? .max) }
    }

    public struct NeedsYouItem: Sendable, Equatable, Identifiable {
        public var id: Int
        public var project: String
        public var label: String
        public var reason: String
        public var age: String
    }

    public struct AgentItem: Sendable, Equatable, Identifiable {
        public var id: Int
        public var project: String
        public var kind: String
        public var attempt: Int?
        public var title: String
        public var stateLabel: String
        public var progress: String
        public var tone: AgentTone
        public var age: String
        public var url: URL?
    }

    public struct Meter: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public var name: String
        /// 0…1, nil when Tower couldn't read it.
        public var fraction: Double?
        public var warn: Bool
        public var text: String { Presentation.percent(fraction.map { $0 * 100 }) }
    }

    public var slots: Slots
    public var queue: Int
    public var needsYou: [NeedsYouItem]
    public var agents: [AgentItem]
    public var meters: [Meter]
    public var warnings: [String]

    public init(_ s: DashSnapshot, now: Date) {
        slots = Slots(occupied: s.slots.occupied, allocated: s.slots.allocated)
        queue = s.projects.filter(\.enabled).reduce(0) { $0 + $1.ready }
        needsYou = s.needsYou.enumerated().map { i, n in
            NeedsYouItem(id: i, project: n.project, label: Self.capitalized(Presentation.needsYouLabel(n.kind)),
                         reason: n.reason, age: Presentation.age(since: n.since, now: now))
        }
        agents = s.agents.enumerated().map { i, a in
            let waiting = !a.awaiting.isEmpty
            let tone: AgentTone
            switch a.state {
            case _ where waiting: tone = .waiting
            case "working": tone = .working
            case "blocked": tone = .blocked
            default: tone = .idle
            }
            return AgentItem(id: i, project: a.project, kind: a.kind, attempt: a.attempt, title: a.title,
                             stateLabel: waiting ? "Waiting for you" : Self.capitalized(a.state.isEmpty ? "starting" : a.state),
                             progress: waiting ? a.awaiting : a.progress, tone: tone,
                             age: Presentation.age(since: a.startedAt, now: now), url: a.url)
        }
        let h = s.host
        let mem = Presentation.ratio(h.memUsedBytes, h.memTotalBytes)
        let diskFree = Presentation.ratio(h.diskFreeBytes, h.diskTotalBytes)
        let cpu = h.cpuPercent.map { $0 / 100 }
        meters = [
            Meter(name: "Memory", fraction: mem, warn: (mem ?? 0) * 100 > Presentation.memLimit),
            Meter(name: "Disk", fraction: diskFree.map { 1 - $0 }, warn: (diskFree ?? 1) * 100 < Presentation.diskFreeLimit),
            Meter(name: "CPU", fraction: cpu, warn: (h.cpuPercent ?? 0) > Presentation.cpuLimit),
        ]
        warnings = s.warnings
    }

    static func capitalized(_ s: String) -> String {
        s.prefix(1).uppercased() + s.dropFirst()
    }
}
