import Foundation

/// Polls Tower's read-only `GET /dash.json` over plain HTTP.
public struct TowerClient: Sendable {
    public static let timeout: TimeInterval = 5

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.timeout
        config.timeoutIntervalForResource = Self.timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    public func fetch(_ address: TowerAddress) async -> FetchOutcome {
        var request = URLRequest(url: address.feedURL)
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Self.classify(status: status, body: data)
        } catch {
            return .offline
        }
    }

    public static func classify(status: Int, body: Data) -> FetchOutcome {
        switch status {
        case 200:
            // Must be a JSON object; anything else (an HTML page, a bare array) is not the feed.
            guard (try? JSONSerialization.jsonObject(with: body)) is [String: Any],
                  let snapshot = try? DashSnapshot.decode(body) else { return .unreadable }
            return .snapshot(snapshot)
        case 503: return .unavailable
        case 421: return .misdirected
        default: return .httpStatus(status)
        }
    }
}
