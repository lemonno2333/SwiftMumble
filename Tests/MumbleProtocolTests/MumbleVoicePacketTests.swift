import Foundation
import Testing
@testable import MumbleProtocol

@Test func protobufAudioCanBeTunneledThroughTCP() throws {
    let frame = try MumbleVoicePacket.tunnelClientAudio(
        opusData: Data([1, 2, 3]),
        frameNumber: 99,
        target: 0
    )

    #expect(frame.type == .udpTunnel)
    #expect(frame.payload.first == 0)

    var serverAudio = MumbleUDP_Audio()
    serverAudio.header = .context(0)
    serverAudio.senderSession = 42
    serverAudio.frameNumber = 99
    serverAudio.opusData = Data([1, 2, 3])
    var serverPacket = Data([0])
    serverPacket.append(try serverAudio.serializedData())

    let decoded = try MumbleVoicePacket.decodeTunneledAudio(
        MumbleFrame(type: .udpTunnel, payload: serverPacket)
    )
    #expect(decoded.senderSession == 42)
    #expect(decoded.frameNumber == 99)
    #expect(decoded.opusData == Data([1, 2, 3]))
    #expect(decoded.volumeAdjustment == 1)
}

@Test func legacyServerListPingRoundTripsExtendedResponse() throws {
    let timestamp: UInt64 = 0x0102030405060708
    let request = MumbleUDPPacket.legacyServerListPing(timestamp: timestamp)
    #expect(request.count == 12)
    // A legacy response leads with the big-endian version u32; a real 1.x/2.x
    // server's high byte is 0x00, which is how the parser tells it from the
    // 0x01-prefixed protobuf format.
    var response = Data([0x00, 0x01, 0x03, 0x04])
    withUnsafeBytes(of: timestamp) { response.append(contentsOf: $0) }
    for value: UInt32 in [5, 20, 72_000] {
        response.append(UInt8(truncatingIfNeeded: value >> 24))
        response.append(UInt8(truncatingIfNeeded: value >> 16))
        response.append(UInt8(truncatingIfNeeded: value >> 8))
        response.append(UInt8(truncatingIfNeeded: value))
    }
    let decodedValue = try MumbleUDPPacket.serverListPingResponse(from: response)
    let decoded = try #require(decodedValue)
    #expect(decoded.timestamp == timestamp)
    #expect(decoded.userCount == 5)
    #expect(decoded.maxUserCount == 20)
}

@Test func protobufServerListPingResponseParsesExtendedInformationOverLegacyLength() throws {
    // A protobuf extended-information response readily exceeds 24 bytes; the old
    // length-based heuristic misread it as legacy. It must be discriminated by
    // the leading 0x01 type byte and parsed as protobuf.
    var message = MumbleUDP_Ping()
    message.timestamp = 0xDEAD_BEEF_DEAD_BEEF
    message.serverVersionV2 = 0x0001_0007_0000
    message.userCount = 123_456
    message.maxUserCount = 456_789
    message.maxBandwidthPerUser = 720_000
    var response = Data([1])
    response.append(try message.serializedData())
    #expect(response.count > 24)

    let decoded = try #require(try MumbleUDPPacket.serverListPingResponse(from: response))
    #expect(decoded.timestamp == 0xDEAD_BEEF_DEAD_BEEF)
    #expect(decoded.serverVersion == 0x0001_0007_0000)
    #expect(decoded.userCount == 123_456)
    #expect(decoded.maxUserCount == 456_789)
    #expect(decoded.maxBandwidthPerUser == 720_000)
}

@Test func legacyOpusPacketUsesMumbleVarInts() throws {
    let legacyVersion = MumbleProtocolVersion(major: 1, minor: 4, patch: 0)
    let frame = try MumbleVoicePacket.tunnelClientAudio(
        opusData: Data([9, 8, 7]),
        frameNumber: 130,
        target: 31,
        protocolVersion: legacyVersion
    )

    #expect(frame.payload.first == 0x9f)

    var serverPacket = Data([0x80])
    serverPacket.append(MumbleVarInt.encode(42))
    serverPacket.append(MumbleVarInt.encode(130))
    serverPacket.append(MumbleVarInt.encode(3))
    serverPacket.append(contentsOf: [9, 8, 7])

    let decoded = try MumbleVoicePacket.decodeTunneledAudio(
        MumbleFrame(type: .udpTunnel, payload: serverPacket)
    )
    #expect(decoded.senderSession == 42)
    #expect(decoded.frameNumber == 130)
    #expect(decoded.opusData == Data([9, 8, 7]))
}

@Test func legacyAudioRejectsSessionBeyondUInt32() throws {
    // A hostile server can encode a full 8-byte session varint in the legacy
    // format. Narrowing to UInt32 must reject it instead of trapping.
    var packet = Data([0x80])
    packet.append(MumbleVarInt.encode(UInt64(UInt32.max) + 1))
    packet.append(MumbleVarInt.encode(1))
    packet.append(MumbleVarInt.encode(0))

    #expect(throws: MumbleVoicePacketError.self) {
        try MumbleVoicePacket.decodeTunneledAudio(
            MumbleFrame(type: .udpTunnel, payload: packet)
        )
    }
}

@Test func legacyAudioAcceptsMaximumUInt32Session() throws {
    var packet = Data([0x80])
    packet.append(MumbleVarInt.encode(UInt64(UInt32.max)))
    packet.append(MumbleVarInt.encode(1))
    packet.append(MumbleVarInt.encode(0))

    let decoded = try MumbleVoicePacket.decodeTunneledAudio(
        MumbleFrame(type: .udpTunnel, payload: packet)
    )
    #expect(decoded.senderSession == UInt32.max)
}
