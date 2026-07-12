import Foundation

/// Message identifiers defined by upstream MumbleProtocol.h.
public enum MumbleMessageType: UInt16, CaseIterable, Sendable {
    case version = 0
    case udpTunnel = 1
    case authenticate = 2
    case ping = 3
    case reject = 4
    case serverSync = 5
    case channelRemove = 6
    case channelState = 7
    case userRemove = 8
    case userState = 9
    case banList = 10
    case textMessage = 11
    case permissionDenied = 12
    case acl = 13
    case queryUsers = 14
    case cryptSetup = 15
    case contextActionModify = 16
    case contextAction = 17
    case userList = 18
    case voiceTarget = 19
    case permissionQuery = 20
    case codecVersion = 21
    case userStats = 22
    case requestBlob = 23
    case serverConfig = 24
    case suggestConfig = 25
    case pluginDataTransmission = 26
}
