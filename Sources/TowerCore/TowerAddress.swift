import Foundation

/// The Tower address setting: an IP literal, optionally with a port
/// (`100.64.0.7`, `100.64.0.7:8090`, `[fd7a::1]:8090`). A pasted `http://…`
/// URL is accepted too. Without a port the dashboard listener's 8090 is used.
public struct TowerAddress: Sendable, Equatable {
    public static let defaultPort = 8090

    /// `host:port`, with IPv6 hosts in brackets.
    public let authority: String

    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["http://", "https://"] where s.lowercased().hasPrefix(scheme) {
            s.removeFirst(scheme.count)
        }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return nil }

        if s.hasPrefix("[") {
            // [v6] or [v6]:port
            guard let close = s.firstIndex(of: "]") else { return nil }
            let rest = s[s.index(after: close)...]
            if rest.isEmpty {
                s += ":\(Self.defaultPort)"
            } else if !rest.hasPrefix(":") || Int(rest.dropFirst()) == nil {
                return nil
            }
        } else if s.filter({ $0 == ":" }).count > 1 {
            s = "[\(s)]:\(Self.defaultPort)"  // bare IPv6
        } else if let colon = s.firstIndex(of: ":") {
            guard Int(s[s.index(after: colon)...]) != nil else { return nil }
        } else {
            s += ":\(Self.defaultPort)"
        }
        authority = s
    }

    public var feedURL: URL { URL(string: "http://\(authority)/dash.json")! }
    public var dashboardURL: URL { URL(string: "http://\(authority)/")! }
}
