import Foundation
import SwiftProtobuf

public struct MumbleIncomingAudio: Equatable, Sendable {
    public var senderSession: UInt32
    public var frameNumber: UInt64
    public var opusData: Data
    public var isTerminator: Bool
    public var volumeAdjustment: Float
}

public enum MumbleVoicePacketError: Error, Equatable {
    case missingMessageType
    case unsupportedMessageType(UInt8)
    case invalidTarget(UInt32)
    case truncatedLegacyPacket
    case sessionOutOfRange(UInt64)
}

public enum MumbleVoicePacket {
    private static let audioMessageType: UInt8 = 0

    public static func tunnelClientAudio(
        opusData: Data,
        frameNumber: UInt64,
        target: UInt32 = 0,
        isTerminator: Bool = false,
        protocolVersion: MumbleProtocolVersion = .current
    ) throws -> MumbleFrame {
        MumbleFrame(
            type: .udpTunnel,
            payload: try clientAudioPacket(
                opusData: opusData,
                frameNumber: frameNumber,
                target: target,
                isTerminator: isTerminator,
                protocolVersion: protocolVersion
            )
        )
    }

    public static func clientAudioPacket(
        opusData: Data,
        frameNumber: UInt64,
        target: UInt32 = 0,
        isTerminator: Bool = false,
        protocolVersion: MumbleProtocolVersion = .current
    ) throws -> Data {
        if !protocolVersion.usesProtobufAudio {
            return try legacyClientAudioPacket(
                opusData: opusData,
                frameNumber: frameNumber,
                target: target,
                isTerminator: isTerminator
            )
        }

        var audio = MumbleUDP_Audio()
        audio.header = .target(target)
        audio.frameNumber = frameNumber
        audio.opusData = opusData
        audio.isTerminator = isTerminator

        var packet = Data([audioMessageType])
        packet.append(try audio.serializedData())
        return packet
    }

    public static func decodeTunneledAudio(_ frame: MumbleFrame) throws -> MumbleIncomingAudio {
        guard let messageType = frame.payload.first else {
            throw MumbleVoicePacketError.missingMessageType
        }
        if messageType & 0xe0 == 0x80 {
            return try decodeLegacyAudio(frame.payload)
        }
        guard messageType == audioMessageType else {
            throw MumbleVoicePacketError.unsupportedMessageType(messageType)
        }

        let message = try MumbleUDP_Audio(serializedBytes: frame.payload.dropFirst())
        return MumbleIncomingAudio(
            senderSession: message.senderSession,
            frameNumber: message.frameNumber,
            opusData: message.opusData,
            isTerminator: message.isTerminator,
            volumeAdjustment: message.volumeAdjustment == 0 ? 1 : message.volumeAdjustment
        )
    }

    private static func legacyClientAudioPacket(
        opusData: Data,
        frameNumber: UInt64,
        target: UInt32,
        isTerminator: Bool
    ) throws -> Data {
        guard target < 32 else { throw MumbleVoicePacketError.invalidTarget(target) }

        var packet = Data([0x80 | UInt8(target)])
        packet.append(MumbleVarInt.encode(frameNumber))
        let size = UInt64(opusData.count) | (isTerminator ? 1 << 13 : 0)
        packet.append(MumbleVarInt.encode(size))
        packet.append(opusData)
        return packet
    }

    private static func decodeLegacyAudio(_ packet: Data) throws -> MumbleIncomingAudio {
        var offset = 1
        guard let senderSession = MumbleVarInt.decode(packet, offset: &offset),
              let frameNumber = MumbleVarInt.decode(packet, offset: &offset),
              let sizeWithFlags = MumbleVarInt.decode(packet, offset: &offset) else {
            throw MumbleVoicePacketError.truncatedLegacyPacket
        }

        let isTerminator = sizeWithFlags & (1 << 13) != 0
        let opusLength = Int(sizeWithFlags & 0x1fff)
        guard packet.count >= offset + opusLength else {
            throw MumbleVoicePacketError.truncatedLegacyPacket
        }
        // Session IDs are 32-bit on the wire; a hostile server can encode a
        // full 8-byte varint here, so reject instead of trapping on narrowing.
        guard let senderSession32 = UInt32(exactly: senderSession) else {
            throw MumbleVoicePacketError.sessionOutOfRange(senderSession)
        }

        return MumbleIncomingAudio(
            senderSession: senderSession32,
            frameNumber: frameNumber,
            opusData: packet.subdata(in: offset..<(offset + opusLength)),
            isTerminator: isTerminator,
            volumeAdjustment: 1
        )
    }
}

enum MumbleVarInt {
    static func encode(_ value: UInt64) -> Data {
        var bytes: [UInt8] = []
        if value < 0x80 {
            bytes.append(UInt8(value))
        } else if value < 0x4000 {
            bytes.append(UInt8((value >> 8) | 0x80))
            bytes.append(UInt8(value & 0xff))
        } else if value < 0x20_0000 {
            bytes.append(UInt8((value >> 16) | 0xc0))
            bytes.append(UInt8((value >> 8) & 0xff))
            bytes.append(UInt8(value & 0xff))
        } else if value < 0x1000_0000 {
            bytes.append(UInt8((value >> 24) | 0xe0))
            bytes.append(UInt8((value >> 16) & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
            bytes.append(UInt8(value & 0xff))
        } else if value < 0x1_0000_0000 {
            bytes.append(0xf0)
            appendBigEndian(value, byteCount: 4, to: &bytes)
        } else {
            bytes.append(0xf4)
            appendBigEndian(value, byteCount: 8, to: &bytes)
        }
        return Data(bytes)
    }

    static func decode(_ data: Data, offset: inout Int) -> UInt64? {
        guard offset < data.count else { return nil }
        let first = data[offset]
        offset += 1

        if first & 0x80 == 0 { return UInt64(first & 0x7f) }
        if first & 0xc0 == 0x80 {
            return read(data, offset: &offset, count: 1).map { UInt64(first & 0x3f) << 8 | $0 }
        }
        if first & 0xe0 == 0xc0 {
            return read(data, offset: &offset, count: 2).map { UInt64(first & 0x1f) << 16 | $0 }
        }
        if first & 0xf0 == 0xe0 {
            return read(data, offset: &offset, count: 3).map { UInt64(first & 0x0f) << 24 | $0 }
        }
        if first & 0xfc == 0xf0 { return read(data, offset: &offset, count: 4) }
        if first & 0xfc == 0xf4 { return read(data, offset: &offset, count: 8) }
        return nil
    }

    private static func appendBigEndian(_ value: UInt64, byteCount: Int, to bytes: inout [UInt8]) {
        for shift in stride(from: (byteCount - 1) * 8, through: 0, by: -8) {
            bytes.append(UInt8((value >> UInt64(shift)) & 0xff))
        }
    }

    private static func read(_ data: Data, offset: inout Int, count: Int) -> UInt64? {
        guard data.count >= offset + count else { return nil }
        var result: UInt64 = 0
        for _ in 0..<count {
            result = result << 8 | UInt64(data[offset])
            offset += 1
        }
        return result
    }
}
