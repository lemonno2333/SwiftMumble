import Foundation
import Testing
@testable import MumbleProtocol

@Test func resyncPolicyStaysQuietWhileDecryptsAreFresh() {
    let policy = MumbleCryptResyncPolicy(staleInterval: 10, requestCooldown: 5)
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(!policy.shouldRequestResync(
        lastGoodAt: now.addingTimeInterval(-4),
        lastRequestAt: nil,
        now: now
    ))
}

@Test func resyncPolicyRequestsAfterStaleInterval() {
    let policy = MumbleCryptResyncPolicy(staleInterval: 10, requestCooldown: 5)
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(policy.shouldRequestResync(
        lastGoodAt: now.addingTimeInterval(-11),
        lastRequestAt: nil,
        now: now
    ))
}

@Test func resyncPolicyRespectsRequestCooldown() {
    let policy = MumbleCryptResyncPolicy(staleInterval: 10, requestCooldown: 5)
    let now = Date(timeIntervalSince1970: 1_000)
    let stale = now.addingTimeInterval(-30)
    // A request went out 2 seconds ago: hold off.
    #expect(!policy.shouldRequestResync(
        lastGoodAt: stale,
        lastRequestAt: now.addingTimeInterval(-2),
        now: now
    ))
    // Cooldown elapsed with the stream still dead: ask again.
    #expect(policy.shouldRequestResync(
        lastGoodAt: stale,
        lastRequestAt: now.addingTimeInterval(-6),
        now: now
    ))
}

@Test func requestCryptResyncEncodesEmptyCryptSetup() throws {
    let frame = try MumbleCommands.requestCryptResync()
    #expect(frame.type == .cryptSetup)
    let message = try frame.decode(as: MumbleProto_CryptSetup.self)
    #expect(!message.hasKey)
    #expect(!message.hasClientNonce)
    #expect(!message.hasServerNonce)
}
