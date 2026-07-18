import Foundation

public struct MumbleStateSnapshot: Equatable, Sendable {
    public var session: UInt32?
    public var welcomeText: String
    public var channels: [MumbleChannel]

    public init(session: UInt32? = nil, welcomeText: String = "", channels: [MumbleChannel] = []) {
        self.session = session
        self.welcomeText = welcomeText
        self.channels = channels
    }
}

public enum MumbleStateChange: Equatable, Sendable {
    case channelsUpdated
    case usersUpdated
    case synchronized(session: UInt32)
}

public struct MumbleServerState: Sendable {
    private struct ChannelRecord: Sendable {
        var id: UInt32
        var parentID: UInt32?
        var name: String
        var position: Int32
        var isTemporary: Bool
        var canEnter: Bool
        var isEnterRestricted: Bool
        var descriptionText: String
        var linkedChannelIDs: [UInt32]
        var maximumUsers: UInt32?
    }

    private struct UserRecord: Sendable {
        var session: UInt32
        var name: String
        var channelID: UInt32
        var selfMute: Bool
        var selfDeaf: Bool
        var serverMute: Bool
        var serverDeaf: Bool
        var certificateHash: String?
        var registeredUserID: UInt32?
        var prioritySpeaker: Bool
        var commentText: String
        var avatarData: Data?
        var commentHash: Data?
        var avatarHash: Data?
        var hasCommentResource: Bool
        var hasAvatarResource: Bool
    }

    private var channels: [UInt32: ChannelRecord] = [:]
    private var users: [UInt32: UserRecord] = [:]
    private var session: UInt32?
    private var welcomeText = ""

    public init() {}

    @discardableResult
    public mutating func apply(_ frame: MumbleFrame) throws -> MumbleStateChange? {
        switch frame.type {
        case .serverSync:
            let message = try frame.decode(as: MumbleProto_ServerSync.self)
            if message.hasSession {
                session = message.session
            }
            if message.hasWelcomeText {
                welcomeText = message.welcomeText
            }
            return session.map(MumbleStateChange.synchronized)

        case .channelState:
            let message = try frame.decode(as: MumbleProto_ChannelState.self)
            guard message.hasChannelID else { return nil }
            var channel = channels[message.channelID] ?? ChannelRecord(
                id: message.channelID,
                parentID: nil,
                name: "Channel \(message.channelID)",
                position: 0,
                isTemporary: false,
                canEnter: true,
                isEnterRestricted: false,
                descriptionText: "",
                linkedChannelIDs: [],
                maximumUsers: nil
            )
            if message.hasParent { channel.parentID = message.parent }
            if message.hasName { channel.name = message.name }
            if message.hasPosition { channel.position = message.position }
            if message.hasTemporary { channel.isTemporary = message.temporary }
            if message.hasCanEnter { channel.canEnter = message.canEnter }
            if message.hasIsEnterRestricted { channel.isEnterRestricted = message.isEnterRestricted }
            if message.hasDescription_p { channel.descriptionText = message.description_p }
            if !message.links.isEmpty { channel.linkedChannelIDs = message.links.sorted() }
            if !message.linksAdd.isEmpty {
                channel.linkedChannelIDs = Array(Set(channel.linkedChannelIDs + message.linksAdd)).sorted()
            }
            if !message.linksRemove.isEmpty {
                channel.linkedChannelIDs.removeAll { message.linksRemove.contains($0) }
            }
            if message.hasMaxUsers { channel.maximumUsers = message.maxUsers == 0 ? nil : message.maxUsers }
            channels[message.channelID] = channel
            return .channelsUpdated

        case .channelRemove:
            let message = try frame.decode(as: MumbleProto_ChannelRemove.self)
            channels.removeValue(forKey: message.channelID)
            users = users.filter { $0.value.channelID != message.channelID }
            return .channelsUpdated

        case .userState:
            let message = try frame.decode(as: MumbleProto_UserState.self)
            guard message.hasSession else { return nil }
            var user = users[message.session] ?? UserRecord(
                session: message.session,
                name: "User \(message.session)",
                channelID: 0,
                selfMute: false,
                selfDeaf: false,
                serverMute: false,
                serverDeaf: false,
                certificateHash: nil,
                registeredUserID: nil,
                prioritySpeaker: false,
                commentText: "",
                avatarData: nil,
                commentHash: nil,
                avatarHash: nil,
                hasCommentResource: false,
                hasAvatarResource: false
            )
            if message.hasName { user.name = message.name }
            if message.hasChannelID { user.channelID = message.channelID }
            if message.hasSelfMute { user.selfMute = message.selfMute }
            if message.hasSelfDeaf { user.selfDeaf = message.selfDeaf }
            if message.hasMute { user.serverMute = message.mute }
            if message.hasDeaf { user.serverDeaf = message.deaf }
            if message.hasHash { user.certificateHash = message.hash }
            if message.hasUserID { user.registeredUserID = message.userID }
            if message.hasPrioritySpeaker { user.prioritySpeaker = message.prioritySpeaker }
            if message.hasComment { user.commentText = message.comment }
            if message.hasCommentHash {
                if !message.hasComment, user.commentHash != message.commentHash { user.commentText = "" }
                user.commentHash = message.commentHash
            }
            if message.hasTexture { user.avatarData = message.texture.isEmpty ? nil : message.texture }
            if message.hasTextureHash {
                if !message.hasTexture, user.avatarHash != message.textureHash { user.avatarData = nil }
                user.avatarHash = message.textureHash
            }
            if message.hasComment || message.hasCommentHash { user.hasCommentResource = true }
            if message.hasTexture || message.hasTextureHash { user.hasAvatarResource = true }
            users[message.session] = user
            return .usersUpdated

        case .userRemove:
            let message = try frame.decode(as: MumbleProto_UserRemove.self)
            users.removeValue(forKey: message.session)
            return .usersUpdated

        default:
            return nil
        }
    }

    public func snapshot() -> MumbleStateSnapshot {
        let rootIDs = channels.values
            .filter { channel in
                guard let parentID = channel.parentID else { return true }
                return channels[parentID] == nil
            }
            .map(\.id)

        let roots = rootIDs
            .sorted(by: channelSort)
            .map { buildChannel(id: $0, visited: []) }

        return MumbleStateSnapshot(
            session: session,
            welcomeText: welcomeText,
            channels: roots
        )
    }

    private func buildChannel(id: UInt32, visited: Set<UInt32>) -> MumbleChannel {
        guard let record = channels[id], !visited.contains(id) else {
            return MumbleChannel(id: id, name: "Invalid channel")
        }

        let childIDs = channels.values
            .filter { $0.parentID == id }
            .map(\.id)
            .sorted(by: channelSort)
        let channelUsers = users.values
            .filter { $0.channelID == id }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map {
                MumbleUser(
                    id: $0.session,
                    name: $0.name,
                    channelID: $0.channelID,
                    isSelfMuted: $0.selfMute,
                    isSelfDeafened: $0.selfDeaf,
                    isMutedByServer: $0.serverMute,
                    isDeafenedByServer: $0.serverDeaf,
                    certificateHash: $0.certificateHash,
                    registeredUserID: $0.registeredUserID,
                    isPrioritySpeaker: $0.prioritySpeaker,
                    commentText: $0.commentText,
                    avatarData: $0.avatarData,
                    hasCommentResource: $0.hasCommentResource,
                    hasAvatarResource: $0.hasAvatarResource
                )
            }

        return MumbleChannel(
            id: record.id,
            parentID: record.parentID,
            name: record.name,
            position: record.position,
            isTemporary: record.isTemporary,
            canEnter: record.canEnter,
            isEnterRestricted: record.isEnterRestricted,
            descriptionText: record.descriptionText,
            linkedChannelIDs: record.linkedChannelIDs,
            maximumUsers: record.maximumUsers,
            users: channelUsers,
            children: childIDs.map { buildChannel(id: $0, visited: visited.union([id])) }
        )
    }

    private func channelSort(_ lhs: UInt32, _ rhs: UInt32) -> Bool {
        guard let left = channels[lhs], let right = channels[rhs] else { return lhs < rhs }
        if left.position != right.position { return left.position < right.position }
        let comparison = left.name.localizedStandardCompare(right.name)
        return comparison == .orderedSame ? left.id < right.id : comparison == .orderedAscending
    }
}
