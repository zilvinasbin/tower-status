import Foundation

/// Tower's `GET /dash.json` feed, schema 2. Only the fields the app shows are
/// decoded; every one is optional with a default so a missing or mistyped field
/// never fails the whole snapshot. Unknown fields are ignored.
public struct DashSnapshot: Decodable, Sendable, Equatable {
    public static let supportedSchema = 2

    public var schema: Int?
    public var generatedAt: Date?
    public var slots: Slots
    public var agents: [Agent]
    public var needsYou: [NeedsYou]
    public var projects: [Project]
    public var host: Host
    public var warnings: [String]

    public init(schema: Int? = supportedSchema, generatedAt: Date? = nil, slots: Slots = Slots(),
                agents: [Agent] = [], needsYou: [NeedsYou] = [], projects: [Project] = [],
                host: Host = Host(), warnings: [String] = []) {
        self.schema = schema
        self.generatedAt = generatedAt
        self.slots = slots
        self.agents = agents
        self.needsYou = needsYou
        self.projects = projects
        self.host = host
        self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey {
        case schema, slots, agents, projects, host, warnings
        case generatedAt = "generated_at"
        case needsYou = "needs_you"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = c.lenient(Int.self, .schema)
        generatedAt = c.lenientDate(.generatedAt)
        slots = c.lenient(Slots.self, .slots) ?? Slots()
        agents = c.lenientArray(Agent.self, .agents)
        needsYou = c.lenientArray(NeedsYou.self, .needsYou)
        projects = c.lenientArray(Project.self, .projects)
        host = c.lenient(Host.self, .host) ?? Host()
        warnings = c.lenientArray(String.self, .warnings)
    }

    public static func decode(_ data: Data) throws -> DashSnapshot {
        try JSONDecoder().decode(DashSnapshot.self, from: data)
    }

    public struct Slots: Decodable, Sendable, Equatable {
        public var allocated: Int?
        public var occupied: Int?

        public init(allocated: Int? = nil, occupied: Int? = nil) {
            self.allocated = allocated
            self.occupied = occupied
        }

        enum CodingKeys: String, CodingKey { case allocated, occupied }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            allocated = c.lenient(Int.self, .allocated)
            occupied = c.lenient(Int.self, .occupied)
        }
    }

    public struct Agent: Decodable, Sendable, Equatable {
        public var project: String
        public var ticket: String
        public var title: String
        public var url: URL?
        public var kind: String
        public var attempt: Int?
        public var state: String
        public var progress: String
        public var awaiting: String
        public var startedAt: Date?

        public init(project: String = "", ticket: String = "", title: String = "", url: URL? = nil,
                    kind: String = "", attempt: Int? = nil, state: String = "", progress: String = "",
                    awaiting: String = "", startedAt: Date? = nil) {
            self.project = project
            self.ticket = ticket
            self.title = title
            self.url = url
            self.kind = kind
            self.attempt = attempt
            self.state = state
            self.progress = progress
            self.awaiting = awaiting
            self.startedAt = startedAt
        }

        enum CodingKeys: String, CodingKey {
            case project, ticket, title, url, kind, attempt, state, progress, awaiting
            case startedAt = "started_at"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            project = c.lenient(String.self, .project) ?? ""
            ticket = c.lenient(String.self, .ticket) ?? ""
            title = c.lenient(String.self, .title) ?? ""
            url = c.lenient(String.self, .url).flatMap { $0.isEmpty ? nil : URL(string: $0) }
            kind = c.lenient(String.self, .kind) ?? ""
            attempt = c.lenient(Int.self, .attempt)
            state = c.lenient(String.self, .state) ?? ""
            progress = c.lenient(String.self, .progress) ?? ""
            awaiting = c.lenient(String.self, .awaiting) ?? ""
            startedAt = c.lenientDate(.startedAt)
        }
    }

    public struct NeedsYou: Decodable, Sendable, Equatable {
        public var kind: String
        public var project: String
        public var ticket: String
        public var reason: String
        public var since: Date?

        public init(kind: String = "", project: String = "", ticket: String = "", reason: String = "", since: Date? = nil) {
            self.kind = kind
            self.project = project
            self.ticket = ticket
            self.reason = reason
            self.since = since
        }

        enum CodingKeys: String, CodingKey { case kind, project, ticket, reason, since }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = c.lenient(String.self, .kind) ?? ""
            project = c.lenient(String.self, .project) ?? ""
            ticket = c.lenient(String.self, .ticket) ?? ""
            reason = c.lenient(String.self, .reason) ?? ""
            since = c.lenientDate(.since)
        }
    }

    public struct Project: Decodable, Sendable, Equatable {
        public var slug: String
        public var enabled: Bool
        /// The queue: items waiting for a slot.
        public var ready: Int

        public init(slug: String = "", enabled: Bool = true, ready: Int = 0) {
            self.slug = slug
            self.enabled = enabled
            self.ready = ready
        }

        enum CodingKeys: String, CodingKey { case slug, enabled, ready }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            slug = c.lenient(String.self, .slug) ?? ""
            enabled = c.lenient(Bool.self, .enabled) ?? true
            ready = c.lenient(Int.self, .ready) ?? 0
        }
    }

    /// Byte figures are `UInt64`: they can exceed 2^53.
    public struct Host: Decodable, Sendable, Equatable {
        public var diskFreeBytes: UInt64?
        public var diskTotalBytes: UInt64?
        public var cpuPercent: Double?
        public var memUsedBytes: UInt64?
        public var memTotalBytes: UInt64?

        public init(diskFreeBytes: UInt64? = nil, diskTotalBytes: UInt64? = nil, cpuPercent: Double? = nil,
                    memUsedBytes: UInt64? = nil, memTotalBytes: UInt64? = nil) {
            self.diskFreeBytes = diskFreeBytes
            self.diskTotalBytes = diskTotalBytes
            self.cpuPercent = cpuPercent
            self.memUsedBytes = memUsedBytes
            self.memTotalBytes = memTotalBytes
        }

        enum CodingKeys: String, CodingKey {
            case diskFreeBytes = "disk_free_bytes"
            case diskTotalBytes = "disk_total_bytes"
            case cpuPercent = "cpu_percent"
            case memUsedBytes = "mem_used_bytes"
            case memTotalBytes = "mem_total_bytes"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            diskFreeBytes = c.lenient(UInt64.self, .diskFreeBytes)
            diskTotalBytes = c.lenient(UInt64.self, .diskTotalBytes)
            cpuPercent = c.lenient(Double.self, .cpuPercent)
            memUsedBytes = c.lenient(UInt64.self, .memUsedBytes)
            memTotalBytes = c.lenient(UInt64.self, .memTotalBytes)
        }
    }
}

// MARK: - Lenient decoding

/// Decodes one array element, or nothing if it doesn't fit.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(T.self)
    }
}

extension KeyedDecodingContainer {
    /// The value, or nil when the key is missing, null or of the wrong type.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// The array without the elements that don't decode; `[]` when missing.
    func lenientArray<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        (lenient([Lossy<T>].self, key) ?? []).compactMap(\.value)
    }

    func lenientDate(_ key: Key) -> Date? {
        lenient(String.self, key).flatMap(TowerDate.parse)
    }
}

/// RFC 3339 timestamps, with or without fractional seconds.
public enum TowerDate {
    public static func parse(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
