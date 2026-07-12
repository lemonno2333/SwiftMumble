import Testing
@testable import MumbleAudio

@Test func pushToTalkHoldClampsToSupportedRange() {
    #expect(PushToTalkHoldConfiguration(milliseconds: -20).milliseconds == 0)
    #expect(PushToTalkHoldConfiguration(milliseconds: 250).milliseconds == 250)
    #expect(PushToTalkHoldConfiguration(milliseconds: 5_000).milliseconds == 1_000)
}
