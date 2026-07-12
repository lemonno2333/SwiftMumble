import Foundation

public struct MumbleACLGroup: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var inherited: Bool
    public var inherit: Bool
    public var inheritable: Bool
    public var addedUserIDs: [UInt32]
    public var removedUserIDs: [UInt32]
    public init(name: String, inherited: Bool = false, inherit: Bool = true, inheritable: Bool = true,
                addedUserIDs: [UInt32] = [], removedUserIDs: [UInt32] = []) {
        self.name = name; self.inherited = inherited; self.inherit = inherit; self.inheritable = inheritable
        self.addedUserIDs = addedUserIDs; self.removedUserIDs = removedUserIDs
    }
}

public struct MumbleACLEntry: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var inherited: Bool
    public var applyHere: Bool
    public var applySubs: Bool
    public var userID: UInt32?
    public var group: String?
    public var grant: UInt32
    public var deny: UInt32
    public init(id: UUID = UUID(), inherited: Bool = false, applyHere: Bool = true, applySubs: Bool = true,
                userID: UInt32? = nil, group: String? = "all", grant: UInt32 = 0, deny: UInt32 = 0) {
        self.id = id; self.inherited = inherited; self.applyHere = applyHere; self.applySubs = applySubs
        self.userID = userID; self.group = group; self.grant = grant; self.deny = deny
    }
}

public struct MumbleACLConfiguration: Equatable, Sendable {
    public var channelID: UInt32
    public var inheritACLs: Bool
    public var groups: [MumbleACLGroup]
    public var entries: [MumbleACLEntry]

    public init(message: MumbleProto_ACL) {
        channelID = message.channelID
        inheritACLs = message.inheritAcls
        groups = message.groups.map {
            MumbleACLGroup(name: $0.name, inherited: $0.inherited, inherit: $0.inherit,
                           inheritable: $0.inheritable, addedUserIDs: $0.add, removedUserIDs: $0.remove)
        }
        entries = message.acls.map {
            MumbleACLEntry(inherited: $0.inherited, applyHere: $0.applyHere, applySubs: $0.applySubs,
                           userID: $0.hasUserID ? $0.userID : nil, group: $0.hasGroup ? $0.group : nil,
                           grant: $0.grant, deny: $0.deny)
        }
    }

    public func message() -> MumbleProto_ACL {
        var message = MumbleProto_ACL()
        message.channelID = channelID
        message.inheritAcls = inheritACLs
        message.query = false
        message.groups = groups.filter { !$0.inherited }.map { group in
            var value = MumbleProto_ACL.ChanGroup()
            value.name = group.name; value.inherit = group.inherit; value.inheritable = group.inheritable
            value.add = group.addedUserIDs; value.remove = group.removedUserIDs
            return value
        }
        message.acls = entries.filter { !$0.inherited }.map { entry in
            var value = MumbleProto_ACL.ChanACL()
            value.applyHere = entry.applyHere; value.applySubs = entry.applySubs
            if let userID = entry.userID { value.userID = userID }
            else { value.group = entry.group ?? "all" }
            value.grant = entry.grant; value.deny = entry.deny
            return value
        }
        return message
    }
}

public struct MumbleRegisteredUser: Identifiable, Equatable, Sendable {
    public var id: UInt32
    public var name: String
    public var lastSeen: String
    public var lastChannelID: UInt32?
    public init(id: UInt32, name: String, lastSeen: String, lastChannelID: UInt32?) {
        self.id = id; self.name = name; self.lastSeen = lastSeen; self.lastChannelID = lastChannelID
    }
}
