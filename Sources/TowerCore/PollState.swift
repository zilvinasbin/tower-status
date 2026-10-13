import Foundation

/// What one poll of `/dash.json` came back with.
public enum FetchOutcome: Sendable, Equatable {
    /// `200` with a JSON object; its `schema` may differ from 2.
    case snapshot(DashSnapshot)
    /// `503`: Tower could not build the snapshot.
    case unavailable
    /// `421`: the `Host` header was not a private IP literal.
    case misdirected
    /// Any other HTTP status.
    case httpStatus(Int)
    /// `200` whose body is not a JSON object.
    case unreadable
    /// Timeout, no route, connection refused.
    case offline
}

/// The app's polling state, advanced by `applying(_:at:)` after every poll.
public struct PollState: Sendable, Equatable {
    public var hasAddress: Bool
    /// The newest snapshot Tower returned; kept through errors.
    public private(set) var lastGood: DashSnapshot?
    public private(set) var lastOutcome: FetchOutcome?
    /// When the current run of failed connections started.
    public private(set) var offlineSince: Date?

    public init(hasAddress: Bool, lastGood: DashSnapshot? = nil) {
        self.hasAddress = hasAddress
        self.lastGood = lastGood
    }

    public func applying(_ outcome: FetchOutcome, at date: Date) -> PollState {
        var next = self
        next.lastOutcome = outcome
        if case .snapshot(let snapshot) = outcome {
            next.lastGood = snapshot
        }
        if outcome == .offline {
            next.offlineSince = offlineSince ?? date
        } else {
            next.offlineSince = nil
        }
        return next
    }

    /// Forgets everything; used when the address changes.
    public func reset(hasAddress: Bool) -> PollState {
        PollState(hasAddress: hasAddress)
    }
}
