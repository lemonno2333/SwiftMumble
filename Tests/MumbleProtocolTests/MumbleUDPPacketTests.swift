import Testing
@testable import MumbleProtocol

@Test func udpPingRoundTripsInLegacyAndProtobufFormats() throws {
    let legacy = MumbleProtocolVersion(major: 1, minor: 3, patch: 4)
    let modern = MumbleProtocolVersion(major: 1, minor: 7, patch: 0)

    let legacyPacket = try MumbleUDPPacket.ping(timestamp: 123_456, protocolVersion: legacy)
    #expect(legacyPacket.first == 0x20)
    #expect(try MumbleUDPPacket.pingTimestamp(from: legacyPacket, protocolVersion: legacy) == 123_456)

    let modernPacket = try MumbleUDPPacket.ping(timestamp: 654_321, protocolVersion: modern)
    #expect(modernPacket.first == 1)
    #expect(try MumbleUDPPacket.pingTimestamp(from: modernPacket, protocolVersion: modern) == 654_321)
}
