import Foundation
import Testing
@testable import MumbleProtocol

@Test func createChannelOmitsServerAssignedID() throws {
    let frame = try MumbleCommands.createChannel(
        parentID: 4,
        name: "Project",
        description: "Build room",
        temporary: true,
        position: 3,
        maximumUsers: 12
    )
    let message = try frame.decode(as: MumbleProto_ChannelState.self)
    #expect(!message.hasChannelID)
    #expect(message.parent == 4)
    #expect(message.name == "Project")
    #expect(message.temporary)
    #expect(message.maxUsers == 12)
}

@Test func updateAndRemoveChannelTargetExistingID() throws {
    let update = try MumbleCommands.updateChannel(
        channelID: 9,
        name: "Renamed",
        description: "Text",
        position: 2,
        maximumUsers: nil
    )
    let state = try update.decode(as: MumbleProto_ChannelState.self)
    #expect(state.channelID == 9)
    #expect(state.maxUsers == 0)

    let remove = try MumbleCommands.removeChannel(channelID: 9)
    #expect(try remove.decode(as: MumbleProto_ChannelRemove.self).channelID == 9)
}

@Test func channelLinkCommandAddsOrRemovesOneLink() throws {
    let add = try MumbleCommands.setChannelLink(channelID: 1, linkedChannelID: 2, linked: true)
    let remove = try MumbleCommands.setChannelLink(channelID: 1, linkedChannelID: 2, linked: false)
    #expect(try add.decode(as: MumbleProto_ChannelState.self).linksAdd == [2])
    #expect(try remove.decode(as: MumbleProto_ChannelState.self).linksRemove == [2])
}

@Test func channelListeningCommandsCarrySessionAndVolume() throws {
    let listen = try MumbleCommands.setChannelListening(session: 7, channelID: 4, listening: true)
    let listenMessage = try listen.decode(as: MumbleProto_UserState.self)
    #expect(listenMessage.session == 7)
    #expect(listenMessage.listeningChannelAdd == [4])

    let volume = try MumbleCommands.setListeningVolume(session: 7, channelID: 4, adjustment: 1.5)
    let volumeMessage = try volume.decode(as: MumbleProto_UserState.self)
    #expect(volumeMessage.listeningVolumeAdjustment.first?.listeningChannel == 4)
    #expect(volumeMessage.listeningVolumeAdjustment.first?.volumeAdjustment == 1.5)
}

@Test func joinChannelBuildsUserStateCommand() throws {
    let frame = try MumbleCommands.joinChannel(session: 7, channelID: 42)
    let message = try frame.decode(as: MumbleProto_UserState.self)

    #expect(frame.type == .userState)
    #expect(message.session == 7)
    #expect(message.channelID == 42)
}

@Test func moveCommandsTargetUserAndChannelParents() throws {
    let user = try MumbleCommands.moveUser(session: 8, toChannel: 12)
    let userState = try user.decode(as: MumbleProto_UserState.self)
    #expect(userState.session == 8)
    #expect(userState.channelID == 12)

    let channel = try MumbleCommands.moveChannel(channelID: 12, toParent: 3)
    let channelState = try channel.decode(as: MumbleProto_ChannelState.self)
    #expect(channelState.channelID == 12)
    #expect(channelState.parent == 3)
}

@Test func textCommandTargetsOneChannel() throws {
    let frame = try MumbleCommands.sendText("hello", toChannel: 3)
    let message = try frame.decode(as: MumbleProto_TextMessage.self)

    #expect(frame.type == .textMessage)
    #expect(message.channelID == [3])
    #expect(message.message == "hello")
}

@Test func selfAudioStateReportsMuteAndDeaf() throws {
    let frame = try MumbleCommands.selfAudioState(session: 9, selfMute: true, selfDeaf: false)
    let message = try frame.decode(as: MumbleProto_UserState.self)

    #expect(frame.type == .userState)
    #expect(message.session == 9)
    #expect(message.selfMute == true)
    #expect(message.selfDeaf == false)
}

@Test func selfAudioStateCarriesDeafenedState() throws {
    let frame = try MumbleCommands.selfAudioState(session: 4, selfMute: true, selfDeaf: true)
    let message = try frame.decode(as: MumbleProto_UserState.self)

    #expect(message.selfMute == true)
    #expect(message.selfDeaf == true)
}

@Test func privateTextTargetsOneSession() throws {
    let frame = try MumbleCommands.sendPrivateText("hi", toSession: 12)
    let message = try frame.decode(as: MumbleProto_TextMessage.self)

    #expect(frame.type == .textMessage)
    #expect(message.session == [12])
    #expect(message.channelID.isEmpty)
    #expect(message.message == "hi")
}

@Test func userStatisticsRequestTargetsOneSession() throws {
    let frame = try MumbleCommands.requestUserStatistics(session: 21)
    let message = try frame.decode(as: MumbleProto_UserStats.self)

    #expect(frame.type == .userStats)
    #expect(message.session == 21)
    #expect(!message.statsOnly)
}

@Test func channelDescriptionRequestTargetsOneChannel() throws {
    let frame = try MumbleCommands.requestChannelDescription(channelID: 17)
    let message = try frame.decode(as: MumbleProto_RequestBlob.self)
    #expect(frame.type == .requestBlob)
    #expect(message.channelDescription == [17])
}

@Test func voiceTargetsSupportUsersAndChannelShouts() throws {
    let userFrame = try MumbleCommands.setVoiceTarget(id: 1, sessions: [4, 8])
    let users = try userFrame.decode(as: MumbleProto_VoiceTarget.self)
    #expect(users.id == 1)
    #expect(users.targets.first?.session == [4, 8])

    let channelFrame = try MumbleCommands.setVoiceTarget(
        id: 2, channelID: 9, includeLinks: true, includeChildren: true
    )
    let channel = try channelFrame.decode(as: MumbleProto_VoiceTarget.self)
    #expect(channel.id == 2)
    #expect(channel.targets.first?.channelID == 9)
    #expect(channel.targets.first?.links == true)
    #expect(channel.targets.first?.children == true)
}

@Test func registrationAndPrioritySpeakerUseUserState() throws {
    let registration = try MumbleCommands.registerUser(session: 7)
    let registerState = try registration.decode(as: MumbleProto_UserState.self)
    #expect(registerState.session == 7)
    #expect(registerState.hasUserID)
    #expect(registerState.userID == 0)

    let priority = try MumbleCommands.setPrioritySpeaker(session: 8, enabled: true)
    let priorityState = try priority.decode(as: MumbleProto_UserState.self)
    #expect(priorityState.session == 8)
    #expect(priorityState.prioritySpeaker)
}

@Test func userResourcesCanBeRequestedAndUpdated() throws {
    let request = try MumbleCommands.requestUserResources(session: 3, comment: true, texture: true)
    let blob = try request.decode(as: MumbleProto_RequestBlob.self)
    #expect(blob.sessionComment == [3])
    #expect(blob.sessionTexture == [3])

    let comment = try MumbleCommands.setUserComment(session: 3, comment: "Hello")
    #expect(try comment.decode(as: MumbleProto_UserState.self).comment == "Hello")
    let texture = try MumbleCommands.setUserTexture(session: 3, texture: Data([1, 2]))
    #expect(try texture.decode(as: MumbleProto_UserState.self).texture == Data([1, 2]))
}

@Test func moderationCommandsCarryServerAudioAndRemovalState() throws {
    let audio = try MumbleCommands.setServerAudioState(session: 5, muted: true, deafened: true)
    let state = try audio.decode(as: MumbleProto_UserState.self)
    #expect(state.mute)
    #expect(state.deaf)

    let ban = try MumbleCommands.removeUser(
        session: 5, reason: "abuse", ban: true, banCertificate: true, banIP: false
    )
    let removal = try ban.decode(as: MumbleProto_UserRemove.self)
    #expect(removal.session == 5)
    #expect(removal.reason == "abuse")
    #expect(removal.ban)
    #expect(removal.banCertificate)
    #expect(!removal.banIp)
}

@Test func aclAndRegisteredUserCommandsUseOfficialMessages() throws {
    let query = try MumbleCommands.requestACL(channelID: 4)
    let acl = try query.decode(as: MumbleProto_ACL.self)
    #expect(acl.channelID == 4)
    #expect(acl.query)

    let users = try MumbleCommands.requestRegisteredUsers()
    #expect(try users.decode(as: MumbleProto_UserList.self).users.isEmpty)
    let remove = try MumbleCommands.updateRegisteredUser(id: 7, name: "")
    let update = try remove.decode(as: MumbleProto_UserList.self)
    #expect(update.users.first?.userID == 7)
    #expect(update.users.first?.name == "")
}

@Test func contextActionTargetsTheSelectedObject() throws {
    let frame = try MumbleCommands.performContextAction("inspect", session: 7)
    let action = try frame.decode(as: MumbleProto_ContextAction.self)
    #expect(action.action == "inspect")
    #expect(action.session == 7)
}
