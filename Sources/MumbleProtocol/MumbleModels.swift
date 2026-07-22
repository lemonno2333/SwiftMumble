import Foundation

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case authenticating
    case connected(session: UInt32)
    case failed(message: String)
}

public struct MumbleServer: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var host: String
    public var port: UInt16
    public var username: String
    public var certificateFingerprint: String?
    public var isFavorite: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = 64738,
        username: String = "",
        certificateFingerprint: String? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.certificateFingerprint = certificateFingerprint
        self.isFavorite = isFavorite
    }
}

public struct MumbleUser: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public var name: String
    public var channelID: UInt32
    public var isSelfMuted: Bool
    public var isSelfDeafened: Bool
    public var isMutedByServer: Bool
    public var isDeafenedByServer: Bool
    public var isTalking: Bool
    public var certificateHash: String?
    public var registeredUserID: UInt32?
    public var isPrioritySpeaker: Bool
    public var commentText: String
    public var avatarData: Data?
    public var hasCommentResource: Bool
    public var hasAvatarResource: Bool

    public var isSuperUser: Bool {
        name.caseInsensitiveCompare("SuperUser") == .orderedSame
    }

    public init(
        id: UInt32,
        name: String,
        channelID: UInt32,
        isSelfMuted: Bool = false,
        isSelfDeafened: Bool = false,
        isMutedByServer: Bool = false,
        isDeafenedByServer: Bool = false,
        isTalking: Bool = false,
        certificateHash: String? = nil,
        registeredUserID: UInt32? = nil,
        isPrioritySpeaker: Bool = false,
        commentText: String = "",
        avatarData: Data? = nil,
        hasCommentResource: Bool = false,
        hasAvatarResource: Bool = false
    ) {
        self.id = id
        self.name = name
        self.channelID = channelID
        self.isSelfMuted = isSelfMuted
        self.isSelfDeafened = isSelfDeafened
        self.isMutedByServer = isMutedByServer
        self.isDeafenedByServer = isDeafenedByServer
        self.isTalking = isTalking
        self.certificateHash = certificateHash
        self.registeredUserID = registeredUserID
        self.isPrioritySpeaker = isPrioritySpeaker
        self.commentText = commentText
        self.avatarData = avatarData
        self.hasCommentResource = hasCommentResource
        self.hasAvatarResource = hasAvatarResource
    }
}

public struct MumbleChannel: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public var parentID: UInt32?
    public var name: String
    public var position: Int32
    public var isTemporary: Bool
    public var canEnter: Bool
    public var isEnterRestricted: Bool
    public var descriptionText: String
    public var linkedChannelIDs: [UInt32]
    public var maximumUsers: UInt32?
    public var users: [MumbleUser]
    public var children: [MumbleChannel]

    public init(
        id: UInt32,
        parentID: UInt32? = nil,
        name: String,
        position: Int32 = 0,
        isTemporary: Bool = false,
        canEnter: Bool = true,
        isEnterRestricted: Bool = false,
        descriptionText: String = "",
        linkedChannelIDs: [UInt32] = [],
        maximumUsers: UInt32? = nil,
        users: [MumbleUser] = [],
        children: [MumbleChannel] = []
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.position = position
        self.isTemporary = isTemporary
        self.canEnter = canEnter
        self.isEnterRestricted = isEnterRestricted
        self.descriptionText = descriptionText
        self.linkedChannelIDs = linkedChannelIDs
        self.maximumUsers = maximumUsers
        self.users = users
        self.children = children
    }
}
