import Foundation

public struct MumblePacketStatistics: Equatable, Sendable {
    public var good: UInt32
    public var late: UInt32
    public var lost: UInt32
    public var resync: UInt32

    public var lossPercent: Double {
        let total = good + late + lost
        return total == 0 ? 0 : Double(lost) * 100 / Double(total)
    }
}

public struct MumbleUserStatistics: Identifiable, Equatable, Sendable {
    public var id: UInt32 { session }
    public var session: UInt32
    public var release: String?
    public var version: String?
    public var operatingSystem: String?
    public var operatingSystemVersion: String?
    public var bandwidth: UInt32?
    public var onlineSeconds: UInt32?
    public var idleSeconds: UInt32?
    public var tcpPackets: UInt32
    public var udpPackets: UInt32
    public var tcpPingMilliseconds: Float
    public var udpPingMilliseconds: Float
    public var fromClient: MumblePacketStatistics?
    public var fromServer: MumblePacketStatistics?
    public var hasStrongCertificate: Bool?
    public var supportsOpus: Bool?

    public init(message: MumbleProto_UserStats) {
        session = message.session
        if message.hasVersion {
            let parsed = MumbleProtocolVersion(message: message.version)
            version = "\(parsed.major).\(parsed.minor).\(parsed.patch)"
            release = message.version.hasRelease ? message.version.release : nil
            operatingSystem = message.version.hasOs ? message.version.os : nil
            operatingSystemVersion = message.version.hasOsVersion ? message.version.osVersion : nil
        }
        bandwidth = message.hasBandwidth ? message.bandwidth : nil
        onlineSeconds = message.hasOnlinesecs ? message.onlinesecs : nil
        idleSeconds = message.hasIdlesecs ? message.idlesecs : nil
        tcpPackets = message.tcpPackets
        udpPackets = message.udpPackets
        tcpPingMilliseconds = message.tcpPingAvg
        udpPingMilliseconds = message.udpPingAvg
        fromClient = message.hasFromClient ? Self.packetStats(message.fromClient) : nil
        fromServer = message.hasFromServer ? Self.packetStats(message.fromServer) : nil
        hasStrongCertificate = message.hasStrongCertificate ? message.strongCertificate : nil
        supportsOpus = message.hasOpus ? message.opus : nil
    }

    private static func packetStats(_ stats: MumbleProto_UserStats.Stats) -> MumblePacketStatistics {
        MumblePacketStatistics(good: stats.good, late: stats.late, lost: stats.lost, resync: stats.resync)
    }
}
