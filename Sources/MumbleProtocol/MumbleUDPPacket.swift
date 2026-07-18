import Foundation
import SwiftProtobuf

public enum MumbleUDPPacket {
    public struct ServerPingResponse: Equatable, Sendable {
        public var timestamp: UInt64
        public var serverVersion: UInt64
        public var userCount: UInt32
        public var maxUserCount: UInt32
        public var maxBandwidthPerUser: UInt32
    }

    public static func legacyServerListPing(timestamp: UInt64) -> Data {
        var data = Data(repeating: 0, count: 12)
        withUnsafeBytes(of: timestamp) { data.replaceSubrange(4..<12, with: $0) }
        return data
    }

    public static func protobufServerListPing(timestamp: UInt64) throws -> Data {
        var message = MumbleUDP_Ping(); message.timestamp = timestamp; message.requestExtendedInformation = true
        var packet = Data([1]); packet.append(try message.serializedData()); return packet
    }

    public static func serverListPingResponse(from packet: Data) throws -> ServerPingResponse? {
        // Discriminate on the leading type byte, not the length: a protobuf
        // response (type 1) carrying extended info readily exceeds 24 bytes, so
        // a length heuristic would misparse it as legacy. Legacy responses begin
        // with 0x00 — the high byte of the big-endian version u32.
        if packet.first == 1 {
            let message = try MumbleUDP_Ping(serializedBytes: packet.dropFirst())
            return ServerPingResponse(timestamp: message.timestamp, serverVersion: message.serverVersionV2,
                                      userCount: message.userCount, maxUserCount: message.maxUserCount,
                                      maxBandwidthPerUser: message.maxBandwidthPerUser)
        }
        guard packet.count >= 24 else { return nil }
        func be32(_ offset: Int) -> UInt32 {
            packet[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
        }
        let timestamp = packet[4..<12].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        return ServerPingResponse(timestamp: timestamp, serverVersion: UInt64(be32(0)),
                                  userCount: be32(12), maxUserCount: be32(16), maxBandwidthPerUser: be32(20))
    }
    public static func ping(timestamp: UInt64, protocolVersion: MumbleProtocolVersion) throws -> Data {
        if protocolVersion.usesProtobufAudio {
            var message = MumbleUDP_Ping()
            message.timestamp = timestamp
            var packet = Data([1])
            packet.append(try message.serializedData())
            return packet
        }

        var packet = Data([0x20])
        packet.append(MumbleVarInt.encode(timestamp))
        return packet
    }

    public static func pingTimestamp(
        from packet: Data,
        protocolVersion: MumbleProtocolVersion
    ) throws -> UInt64? {
        guard let first = packet.first else { return nil }
        if protocolVersion.usesProtobufAudio {
            guard first == 1 else { return nil }
            return try MumbleUDP_Ping(serializedBytes: packet.dropFirst()).timestamp
        }

        guard first & 0xe0 == 0x20 else { return nil }
        var offset = 1
        return MumbleVarInt.decode(packet, offset: &offset)
    }
}
