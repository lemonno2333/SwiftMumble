import Foundation

/// Tracks which speaker sessions are currently producing audio. A session is
/// marked talking when a voice frame arrives and cleared on an explicit
/// terminator frame or after a short silence timeout. Pure value type so the
/// timeout behavior can be unit tested with an injected clock.
public struct TalkingStateTracker: Sendable {
    public let timeout: TimeInterval
    private var lastActivity: [UInt32: TimeInterval] = [:]

    public init(timeout: TimeInterval = 0.25) {
        precondition(timeout > 0)
        self.timeout = timeout
    }

    public var talkingSessions: Set<UInt32> {
        Set(lastActivity.keys)
    }

    public func isTalking(_ session: UInt32) -> Bool {
        lastActivity[session] != nil
    }

    /// Records a voice frame for a session. Returns true if the set of talking
    /// sessions changed (i.e. this session was not already talking).
    @discardableResult
    public mutating func markActive(session: UInt32, now: TimeInterval) -> Bool {
        let wasTalking = lastActivity[session] != nil
        lastActivity[session] = now
        return !wasTalking
    }

    /// Clears a session immediately (terminator frame or user left).
    @discardableResult
    public mutating func clear(session: UInt32) -> Bool {
        lastActivity.removeValue(forKey: session) != nil
    }

    /// Removes sessions whose last frame is older than the timeout. Returns true
    /// if anything was removed.
    @discardableResult
    public mutating func pruneExpired(now: TimeInterval) -> Bool {
        let expired = lastActivity.filter { now - $0.value >= timeout }.map(\.key)
        for session in expired { lastActivity.removeValue(forKey: session) }
        return !expired.isEmpty
    }

    public mutating func reset() {
        lastActivity.removeAll()
    }
}
