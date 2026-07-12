import Testing
@testable import MumbleProtocol

@Test func reconnectPolicyBacksOffExponentiallyAndCaps() {
    var policy = MumbleReconnectPolicy(
        baseDelay: 2,
        maximumDelay: 30,
        multiplier: 2,
        maximumAttempts: 10
    )

    #expect(policy.nextDelay() == 2)
    #expect(policy.nextDelay() == 4)
    #expect(policy.nextDelay() == 8)
    #expect(policy.nextDelay() == 16)
    // 2 * 2^4 = 32 clamps to the 30 s ceiling.
    #expect(policy.nextDelay() == 30)
    #expect(policy.nextDelay() == 30)
}

@Test func reconnectPolicyStopsAfterMaximumAttempts() {
    var policy = MumbleReconnectPolicy(baseDelay: 1, maximumDelay: 4, multiplier: 2, maximumAttempts: 3)

    #expect(policy.nextDelay() == 1)
    #expect(policy.nextDelay() == 2)
    #expect(policy.nextDelay() == 4)
    #expect(policy.canRetry == false)
    #expect(policy.nextDelay() == nil)
}

@Test func reconnectPolicyResetsBudget() {
    var policy = MumbleReconnectPolicy(baseDelay: 1, maximumDelay: 4, multiplier: 2, maximumAttempts: 2)

    _ = policy.nextDelay()
    _ = policy.nextDelay()
    #expect(policy.canRetry == false)

    policy.reset()
    #expect(policy.canRetry == true)
    #expect(policy.nextDelay() == 1)
}
