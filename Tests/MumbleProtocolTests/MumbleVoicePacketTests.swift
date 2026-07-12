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
    var response = Data([1, 2, 3, 4])
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
