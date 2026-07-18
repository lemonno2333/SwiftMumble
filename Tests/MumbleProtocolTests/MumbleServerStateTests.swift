import Foundation
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

@Test func serverStateInvalidatesUserResourcesWhenHashesChange() throws {
    var state = MumbleServerState()

    var root = MumbleProto_ChannelState()
    root.channelID = 0
    root.name = "Root"
    try state.apply(MumbleFrame(type: .channelState, message: root))

    var initial = MumbleProto_UserState()
    initial.session = 7
    initial.name = "User"
    initial.channelID = 0
    initial.comment = "Old comment"
    initial.commentHash = Data([1])
    initial.texture = Data([2, 3])
    initial.textureHash = Data([4])
    try state.apply(MumbleFrame(type: .userState, message: initial))

    var changedHashes = MumbleProto_UserState()
    changedHashes.session = 7
    changedHashes.commentHash = Data([5])
    changedHashes.textureHash = Data([6])
    try state.apply(MumbleFrame(type: .userState, message: changedHashes))

    let user = try #require(state.snapshot().channels.first?.users.first)
    #expect(user.commentText.isEmpty)
    #expect(user.avatarData == nil)
    #expect(user.hasCommentResource)
    #expect(user.hasAvatarResource)
}

@Test func serverStateKeepsResourcesDeliveredWithTheirHashes() throws {
    var state = MumbleServerState()

    var root = MumbleProto_ChannelState()
    root.channelID = 0
    root.name = "Root"
    try state.apply(MumbleFrame(type: .channelState, message: root))

    var userState = MumbleProto_UserState()
    userState.session = 8
    userState.name = "User"
    userState.channelID = 0
    userState.comment = "Fresh comment"
    userState.commentHash = Data([1, 2])
    userState.texture = Data([3, 4])
    userState.textureHash = Data([5, 6])
    try state.apply(MumbleFrame(type: .userState, message: userState))

    let user = try #require(state.snapshot().channels.first?.users.first)
    #expect(user.commentText == "Fresh comment")
    #expect(user.avatarData == Data([3, 4]))
}
