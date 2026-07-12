import Foundation

/// Exponential backoff schedule for automatic reconnection. Pure value type so
/// the delay sequence can be unit tested without timers.
public struct MumbleReconnectPolicy: Equatable, Sendable {
    public let baseDelay: TimeInterval
    public let maximumDelay: TimeInterval
    public let multiplier: Double
    public let maximumAttempts: Int
    public private(set) var attempt = 0

    public init(
        baseDelay: TimeInterval = 2,
        maximumDelay: TimeInterval = 30,
        multiplier: Double = 2,
        maximumAttempts: Int = 10
    ) {
        precondition(baseDelay > 0)
        precondition(maximumDelay >= baseDelay)
        precondition(multiplier >= 1)
        precondition(maximumAttempts >= 0)
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
        self.multiplier = multiplier
        self.maximumAttempts = maximumAttempts
    }

    public var canRetry: Bool {
        attempt < maximumAttempts
    }

    /// Advances to the next attempt and returns its delay, or nil once the
    /// attempt budget is exhausted.
    public mutating func nextDelay() -> TimeInterval? {
        guard attempt < maximumAttempts else { return nil }
        let delay = min(maximumDelay, baseDelay * pow(multiplier, Double(attempt)))
        attempt += 1
        return delay
    }

    public mutating func reset() {
        attempt = 0
    }
}
