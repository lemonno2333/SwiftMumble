import Foundation

public enum MumbleCommands {
    public static func createChannel(
        parentID: UInt32,
        name: String,
        description: String = "",
        temporary: Bool = false,
        position: Int32 = 0,
        maximumUsers: UInt32? = nil
    ) throws -> MumbleFrame {
        var message = MumbleProto_ChannelState()
        message.parent = parentID
        message.name = name
        message.description_p = description
        message.temporary = temporary
        message.position = position
        if let maximumUsers { message.maxUsers = maximumUsers }
        return try MumbleFrame(type: .channelState, message: message)
    }

    public static func updateChannel(
        channelID: UInt32,
        name: String,
        description: String,
        position: Int32,
        maximumUsers: UInt32?
    ) throws -> MumbleFrame {
        var message = MumbleProto_ChannelState()
        message.channelID = channelID
        message.name = name
        message.description_p = description
        message.position = position
        message.maxUsers = maximumUsers ?? 0
        return try MumbleFrame(type: .channelState, message: message)
    }

    public static func removeChannel(channelID: UInt32) throws -> MumbleFrame {
        var message = MumbleProto_ChannelRemove()
        message.channelID = channelID
        return try MumbleFrame(type: .channelRemove, message: message)
    }

    public static func setChannelLink(
        channelID: UInt32,
        linkedChannelID: UInt32,
        linked: Bool
    ) throws -> MumbleFrame {
        var message = MumbleProto_ChannelState()
        message.channelID = channelID
        if linked { message.linksAdd = [linkedChannelID] }
        else { message.linksRemove = [linkedChannelID] }
        return try MumbleFrame(type: .channelState, message: message)
    }

    public static func setChannelListening(
        session: UInt32,
        channelID: UInt32,
        listening: Bool
    ) throws -> MumbleFrame {
        var message = MumbleProto_UserState()
        message.session = session
        if listening { message.listeningChannelAdd = [channelID] }
        else { message.listeningChannelRemove = [channelID] }
        return try MumbleFrame(type: .userState, message: message)
    }

    public static func setListeningVolume(
        session: UInt32,
        channelID: UInt32,
        adjustment: Float
    ) throws -> MumbleFrame {
        var message = MumbleProto_UserState()
        message.session = session
        var volume = MumbleProto_UserState.VolumeAdjustment()
        volume.listeningChannel = channelID
        volume.volumeAdjustment = min(2, max(0, adjustment))
        message.listeningVolumeAdjustment = [volume]
        return try MumbleFrame(type: .userState, message: message)
    }

    public static func joinChannel(session: UInt32, channelID: UInt32) throws -> MumbleFrame {
        var message = MumbleProto_UserState()
        message.session = session
        message.channelID = channelID
        return try MumbleFrame(type: .userState, message: message)
    }

    public static func moveUser(session: UInt32, toChannel channelID: UInt32) throws -> MumbleFrame {
        try joinChannel(session: session, channelID: channelID)
    }

    public static func moveChannel(channelID: UInt32, toParent parentID: UInt32) throws -> MumbleFrame {
        var message = MumbleProto_ChannelState()
        message.channelID = channelID
        message.parent = parentID
        return try MumbleFrame(type: .channelState, message: message)
    }

    public static func sendText(_ text: String, toChannel channelID: UInt32) throws -> MumbleFrame {
        var message = MumbleProto_TextMessage()
        message.channelID = [channelID]
        message.message = text
        return try MumbleFrame(type: .textMessage, message: message)
    }

    /// Direct (private) text message to a single user session.
    public static func sendPrivateText(_ text: String, toSession session: UInt32) throws -> MumbleFrame {
        var message = MumbleProto_TextMessage()
        message.session = [session]
        message.message = text
        return try MumbleFrame(type: .textMessage, message: message)
    }

    public static func requestUserStatistics(session: UInt32, statsOnly: Bool = false) throws -> MumbleFrame {
        var message = MumbleProto_UserStats()
        message.session = session
        message.statsOnly = statsOnly
        return try MumbleFrame(type: .userStats, message: message)
    }

    public static func requestChannelDescription(channelID: UInt32) throws -> MumbleFrame {
        var message = MumbleProto_RequestBlob()
        message.channelDescription = [channelID]
        return try MumbleFrame(type: .requestBlob, message: message)
    }

    public static func requestUserResources(session: UInt32, comment: Bool, texture: Bool) throws -> MumbleFrame {
        var message = MumbleProto_RequestBlob()
        if comment { message.sessionComment = [session] }
        if texture { message.sessionTexture = [session] }
        return try MumbleFrame(type: .requestBlob, message: message)
    }

    public static func setUserComment(session: UInt32, comment: String) throws -> MumbleFrame {
        var message = MumbleProto_UserState()
        message.session = session
        message.comment = comment
        return try MumbleFrame(type: .userState, message: message)
    }

    public static func setUserTexture(session: UInt32, texture: Data) throws -> MumbleFrame {
        var message = MumbleProto_UserState()
        message.session = session
        message.texture = texture
        return try MumbleFrame(type: .userState, message: message)
    }

    public static func setVoiceTarget(id: UInt32, sessions: [UInt32]) throws -> MumbleFrame {
        var message = MumbleProto_VoiceTarget()
        message.id = min(30, max(1, id))
        var target = MumbleProto_VoiceTarget.Target()
        target.session = sessions
        message.targets = sessions.isEmpty ? [] : [target]
        return try MumbleFrame(type: .voiceTarget, message: message)
    }

    public static func setVoiceTarget(
        id: UInt32,
        channelID: UInt32,
        includeLinks: Bool = false,
        includeChildren: Bool = false
    ) throws -> MumbleFrame {
        var message = MumbleProto_VoiceTarget()
        message.id = min(30, max(1, id))
        var target = MumbleProto_VoiceTarget.Target()
        target.channelID = channelID
        target.links = includeLinks
        target.children = includeChildren
        message.targets = [target]
        return try MumbleFrame(type: .voiceTarget, message: message)
    }

    /// Reports the local user's self-mute and self-deafen state to the server so
    /// other clients see it. Sent as a single UserState carrying both fields,
    /// matching how the official client updates its own state.
    public static func selfAudioState(
        session: UInt32,
        selfMute: Bool,
        selfDeaf: Bool
    ) throws -> MumbleFrame {
        var message = MumbleProto_UserState()
        message.session = session
        message.selfMute = selfMute
        message.selfDeaf = selfDeaf
        return try MumbleFrame(type: .userState, message: message)
    }

    public static func registerUser(session: UInt32) throws -> MumbleFrame {
        var message = MumbleProto_UserState()
        message.session = session
        message.userID = 0
        return try MumbleFrame(type: .userState, message: message)
    }

    public static func setPrioritySpeaker(session: UInt32, enabled: Bool) throws -> MumbleFrame {
        var message = MumbleProto_UserState()
        message.session = session
        message.prioritySpeaker = enabled
        return try MumbleFrame(type: .userState, message: message)
    }

    public static func setServerAudioState(
        session: UInt32,
        muted: Bool? = nil,
        deafened: Bool? = nil
    ) throws -> MumbleFrame {
        var message = MumbleProto_UserState()
        message.session = session
        if let muted { message.mute = muted }
        if let deafened { message.deaf = deafened }
        return try MumbleFrame(type: .userState, message: message)
    }

    public static func removeUser(
        session: UInt32,
        reason: String,
        ban: Bool,
        banCertificate: Bool = true,
        banIP: Bool = false
    ) throws -> MumbleFrame {
        var message = MumbleProto_UserRemove()
        message.session = session
        message.reason = reason
        message.ban = ban
        if ban {
            message.banCertificate = banCertificate
            message.banIp = banIP
        }
        return try MumbleFrame(type: .userRemove, message: message)
    }

    public static func requestACL(channelID: UInt32) throws -> MumbleFrame {
        var message = MumbleProto_ACL(); message.channelID = channelID; message.query = true
        return try MumbleFrame(type: .acl, message: message)
    }

    public static func setACL(_ configuration: MumbleACLConfiguration) throws -> MumbleFrame {
        try MumbleFrame(type: .acl, message: configuration.message())
    }

    public static func requestRegisteredUsers() throws -> MumbleFrame {
        try MumbleFrame(type: .userList, message: MumbleProto_UserList())
    }

    public static func updateRegisteredUser(id: UInt32, name: String) throws -> MumbleFrame {
        var message = MumbleProto_UserList(); var user = MumbleProto_UserList.User()
        user.userID = id; user.name = name; message.users = [user]
        return try MumbleFrame(type: .userList, message: message)
    }

    public static func performContextAction(_ action: String, session: UInt32? = nil, channelID: UInt32? = nil) throws -> MumbleFrame {
        var message = MumbleProto_ContextAction(); message.action = action
        if let session { message.session = session }; if let channelID { message.channelID = channelID }
        return try MumbleFrame(type: .contextAction, message: message)
    }
}
