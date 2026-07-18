import Foundation

/// Decides when the client should ask the server to resynchronize the OCB2
/// crypt state (by sending an empty CryptSetup over TCP).
///
/// The client pings over UDP every few seconds, so a healthy link produces a
/// successfully decrypted packet at least that often. When raw UDP keeps
/// flowing but nothing has decrypted for `staleInterval`, the nonce streams
/// have desynchronized — voice would otherwise stay dead (or stuck on the TCP
/// tunnel) until reconnect. Requests are rate-limited by `requestCooldown`.
public struct MumbleCryptResyncPolicy: Equatable, Sendable {
    public var staleInterval: TimeInterval
    public var requestCooldown: TimeInterval

    public init(staleInterval: TimeInterval = 10, requestCooldown: TimeInterval = 5) {
        precondition(staleInterval > 0)
        precondition(requestCooldown > 0)
        self.staleInterval = staleInterval
        self.requestCooldown = requestCooldown
    }

    /// - Parameters:
    ///   - lastGoodAt: time of the last successfully decrypted UDP packet, or
    ///     the moment the UDP session started if nothing has decrypted yet.
    ///   - lastRequestAt: time of the previous resync request, if any.
    public func shouldRequestResync(
        lastGoodAt: Date,
        lastRequestAt: Date?,
        now: Date
    ) -> Bool {
        guard now.timeIntervalSince(lastGoodAt) > staleInterval else { return false }
        guard let lastRequestAt else { return true }
        return now.timeIntervalSince(lastRequestAt) > requestCooldown
    }
}
