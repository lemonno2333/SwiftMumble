import Testing
@testable import MumbleProtocol

@Test func serverStateBuildsChannelAndUserTreeFromIncrementalMessages() throws {
    var state = MumbleServerState()

    var root = MumbleProto_ChannelState()
    root.channelID = 0
    root.name = "Root"
    try state.apply(MumbleFrame(type: .channelState, message: root))

    var lounge = MumbleProto_ChannelState()
    lounge.channelID = 1
    lounge.parent = 0
    lounge.name = "Lounge"
    lounge.position = 10
    try state.apply(MumbleFrame(type: .channelState, message: lounge))

    var user = MumbleProto_UserState()
    user.session = 42
    user.name = "Leo"
    user.channelID = 1
    user.selfMute = true
    user.hash = "certificate-hash"
    try state.apply(MumbleFrame(type: .userState, message: user))

    var sync = MumbleProto_ServerSync()
    sync.session = 42
    sync.welcomeText = "Welcome"
    let change = try state.apply(MumbleFrame(type: .serverSync, message: sync))

    let snapshot = state.snapshot()
    #expect(change == .synchronized(session: 42))
    #expect(snapshot.session == 42)
    #expect(snapshot.welcomeText == "Welcome")
    #expect(snapshot.channels.first?.name == "Root")
    #expect(snapshot.channels.first?.children.first?.name == "Lounge")
    #expect(snapshot.channels.first?.children.first?.users.first?.name == "Leo")
    #expect(snapshot.channels.first?.children.first?.users.first?.isSelfMuted == true)
    #expect(snapshot.channels.first?.children.first?.users.first?.certificateHash == "certificate-hash")
}
