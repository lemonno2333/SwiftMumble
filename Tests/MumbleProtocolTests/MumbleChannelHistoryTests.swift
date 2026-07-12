import Testing
@testable import MumbleProtocol

@Test func channelHistoryTracksThePreviousDistinctChannel() {
    var history = MumbleChannelHistory()

    let observedFirst = history.observe(channelID: 1)
    #expect(observedFirst)
    #expect(history.previousChannelID == nil)
    let observedDuplicate = history.observe(channelID: 1)
    #expect(!observedDuplicate)
    let observedSecond = history.observe(channelID: 2)
    #expect(observedSecond)
    #expect(history.currentChannelID == 2)
    #expect(history.previousChannelID == 1)
}

@Test func channelHistorySupportsReturningBetweenTheLastTwoChannels() {
    var history = MumbleChannelHistory()
    history.observe(channelID: 4)
    history.observe(channelID: 9)

    let returnTarget = history.previousChannelID
    #expect(returnTarget == 4)
    history.observe(channelID: returnTarget!)
    #expect(history.currentChannelID == 4)
    #expect(history.previousChannelID == 9)
}

@Test func channelHistoryResetClearsBothChannels() {
    var history = MumbleChannelHistory()
    history.observe(channelID: 3)
    history.observe(channelID: 7)

    history.reset()

    #expect(history.currentChannelID == nil)
    #expect(history.previousChannelID == nil)
}
