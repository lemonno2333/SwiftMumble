import Testing
@testable import MumbleProtocol

@Test func messageIdentifiersMatchUpstreamProtocol() {
    #expect(MumbleMessageType.version.rawValue == 0)
    #expect(MumbleMessageType.authenticate.rawValue == 2)
    #expect(MumbleMessageType.serverSync.rawValue == 5)
    #expect(MumbleMessageType.channelState.rawValue == 7)
    #expect(MumbleMessageType.userState.rawValue == 9)
    #expect(MumbleMessageType.pluginDataTransmission.rawValue == 26)
}
