import Foundation

/// Everything the menu bar item and its menu show, derived from `PollState`
/// by the display rules (spec sections 4 and 5). Pure, so it is unit-tested.
public struct Presentation: Sendable, Equatable {
    public enum Tone: Sendable, Equatable { case normal, warning }

    public struct Line: Sendable, Equatable {
        public var text: String
        public var tone: Tone
        public var url: URL?

        public init(_ text: String, tone: Tone = .normal, url: URL? = nil) {
            self.text = text
            self.tone = tone
            self.url = url
        }
    }

    /// Generated_at older than this means "stale".
    public static let staleAfter: TimeInterval = 60
    public static let memLimit = 90.0, cpuLimit = 90.0, diskFreeLimit = 10.0

    public var title: String
    public var titleDimmed: Bool
    /// Status lines shown above the data ("offline since 14:02", "stale", …).
    public var messages: [String]
    /// True when the data is old (offline, stale, error): the menu dims it.
    public var dataDimmed: Bool
    /// Nil when there is no snapshot to show.
    public var data: DataLines?

    public struct DataLines: Sendable, Equatable {
        public var slots: Line
        public var needsYou: Line
        public var needsYouRows: [Line]
        public var queue: Line
        public var host: Line
        public var agents: [Line]
        public var warnings: [String]
        /// Count of `needs_you`, for the title and notifications.
        public var needsYouCount: Int
    }

    public init(state: PollState, now: Date, timeZone: TimeZone = .current) {
        guard state.hasAddress else {
            self.init(title: "T –", titleDimmed: true, messages: ["Set the Tower address in Settings"],
                      dataDimmed: false, data: nil)
            return
        }

        let snapshot = state.lastGood
        let data = snapshot.map { Self.dataLines(for: $0, now: now) }
        let stale = snapshot?.generatedAt.map { now.timeIntervalSince($0) > Self.staleAfter } ?? false

        var messages: [String] = []
        var answered = false  // Tower answered with something usable this poll
        switch state.lastOutcome {
        case nil:
            messages.append("Connecting…")
        case .snapshot(let s):
            answered = true
            if s.schema != DashSnapshot.supportedSchema {
                messages.append("Tower schema \(s.schema.map(String.init) ?? "?"): update the app")
            }
        case .unavailable:
            answered = true
            messages.append("Tower: snapshot unavailable")
        case .misdirected:
            messages.append("Use the IP address, not a host name")
        case .httpStatus(let code):
            messages.append("Tower: HTTP \(code)")
        case .unreadable:
            messages.append("Tower: unreadable response")
        case .offline:
            let since = state.offlineSince.map { Self.clock($0, timeZone: timeZone) } ?? "now"
            messages.append("offline since \(since)")
        }
        if stale && snapshot != nil {
            messages.append("stale")
        }

        let live = answered && !stale && data != nil
        var title = "T –"
        if live, let data, let slots = snapshot?.slots {
            title = "T \(Self.slotsText(slots))"
            if data.needsYouCount > 0 { title += " · ⚠\(data.needsYouCount)" }
        }
        self.init(title: title, titleDimmed: !live, messages: messages,
                  dataDimmed: data != nil && !live, data: data)
    }

    init(title: String, titleDimmed: Bool, messages: [String], dataDimmed: Bool, data: DataLines?) {
        self.title = title
        self.titleDimmed = titleDimmed
        self.messages = messages
        self.dataDimmed = dataDimmed
        self.data = data
    }

    // MARK: - Lines

    static func dataLines(for s: DashSnapshot, now: Date) -> DataLines {
        let overbooked = (s.slots.occupied ?? 0) > (s.slots.allocated ?? .max)
        let slots = Line("Slots: \(slotsText(s.slots))\(overbooked ? " ⚠" : "")",
                         tone: overbooked ? .warning : .normal)

        let queue = s.projects.filter(\.enabled).reduce(0) { $0 + $1.ready }

        let needsYouRows = s.needsYou.map { n in
            Line([n.project, needsYouLabel(n.kind), n.reason, age(since: n.since, now: now)]
                .filter { !$0.isEmpty }
                .joined(separator: " · "))
        }

        let agents = s.agents.map { a in
            let attempt = a.attempt.map { " #\($0)" } ?? ""
            let state = a.awaiting.isEmpty ? (a.state.isEmpty ? "–" : a.state) : "waiting for you"
            return Line("\(a.project) · \(a.kind)\(attempt) · \(state) · \(age(since: a.startedAt, now: now))",
                        tone: a.awaiting.isEmpty ? .normal : .warning, url: a.url)
        }

        return DataLines(
            slots: slots,
            needsYou: Line("Needs you: \(s.needsYou.count)", tone: s.needsYou.isEmpty ? .normal : .warning),
            needsYouRows: needsYouRows,
            queue: Line("Queue: \(queue)"),
            host: hostLine(s.host),
            agents: agents,
            warnings: s.warnings,
            needsYouCount: s.needsYou.count
        )
    }

    static func hostLine(_ h: DashSnapshot.Host) -> Line {
        let mem = ratio(h.memUsedBytes, h.memTotalBytes).map { $0 * 100 }
        let diskFree = ratio(h.diskFreeBytes, h.diskTotalBytes).map { $0 * 100 }
        let cpu = h.cpuPercent

        let memWarn = (mem ?? 0) > memLimit
        let diskWarn = (diskFree ?? 100) < diskFreeLimit
        let cpuWarn = (cpu ?? 0) > cpuLimit

        func figure(_ name: String, _ value: Double?, _ warn: Bool) -> String {
            "\(name) \(percent(value))\(warn ? " ⚠" : "")"
        }
        let text = "Host: " + [
            figure("MEM", mem, memWarn),
            figure("DISK", diskFree.map { 100 - $0 }, diskWarn),
            figure("CPU", cpu, cpuWarn),
        ].joined(separator: " · ")
        return Line(text, tone: memWarn || diskWarn || cpuWarn ? .warning : .normal)
    }

    // MARK: - Formatting

    public static func slotsText(_ slots: DashSnapshot.Slots) -> String {
        "\(slots.occupied.map(String.init) ?? "–")/\(slots.allocated.map(String.init) ?? "–")"
    }

    static func ratio(_ part: UInt64?, _ whole: UInt64?) -> Double? {
        guard let part, let whole, whole > 0 else { return nil }
        return Double(part) / Double(whole)
    }

    static func percent(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "–"
    }

    public static func needsYouLabel(_ kind: String) -> String {
        switch kind {
        case "awaiting_input": "waits for input"
        case "blocked": "blocked"
        case "handoff": "review handoff"
        case "notes": "notes to approve"
        default: kind
        }
    }

    /// `45s`, `12m`, `3h 5m`, `2d`.
    public static func age(since date: Date?, now: Date) -> String {
        guard let date else { return "–" }
        let s = max(0, Int(now.timeIntervalSince(date)))
        switch s {
        case ..<60: return "\(s)s"
        case ..<3600: return "\(s / 60)m"
        case ..<86400:
            let m = s % 3600 / 60
            return m == 0 ? "\(s / 3600)h" : "\(s / 3600)h \(m)m"
        default: return "\(s / 86400)d"
        }
    }

    static func clock(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
