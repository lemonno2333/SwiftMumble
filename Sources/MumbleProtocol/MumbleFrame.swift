import Foundation

public struct MumbleFrame: Equatable, Sendable {
    public static let headerLength = 6

    public let type: MumbleMessageType
    public let payload: Data

    public init(type: MumbleMessageType, payload: Data) {
        self.type = type
        self.payload = payload
    }

    public func encoded() -> Data {
        var data = Data(capacity: Self.headerLength + payload.count)
        data.appendBigEndian(type.rawValue)
        data.appendBigEndian(UInt32(payload.count))
        data.append(payload)
        return data
    }
}

public enum MumbleFrameError: Error, Equatable {
    case unknownMessageType(UInt16)
    case payloadTooLarge(Int)
}

/// Incremental decoder for the framed Mumble TCP control stream.
public struct MumbleFrameDecoder: Sendable {
    public var maximumPayloadLength: Int
    private var buffer = Data()

    public init(maximumPayloadLength: Int = 8 * 1024 * 1024) {
        self.maximumPayloadLength = maximumPayloadLength
    }

    public mutating func append(_ bytes: Data) throws -> [MumbleFrame] {
        buffer.append(bytes)
        var frames: [MumbleFrame] = []

        while buffer.count >= MumbleFrame.headerLength {
            let rawType = buffer.readUInt16(at: 0)
            let payloadLength = Int(buffer.readUInt32(at: 2))

            guard payloadLength <= maximumPayloadLength else {
                throw MumbleFrameError.payloadTooLarge(payloadLength)
            }
            guard let type = MumbleMessageType(rawValue: rawType) else {
                throw MumbleFrameError.unknownMessageType(rawType)
            }

            let frameLength = MumbleFrame.headerLength + payloadLength
            guard buffer.count >= frameLength else { break }

            let payload = buffer.subdata(in: MumbleFrame.headerLength..<frameLength)
            frames.append(MumbleFrame(type: type, payload: payload))
            buffer.removeSubrange(0..<frameLength)
        }

        return frames
    }
}

private extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var bigEndianValue = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndianValue) { append(contentsOf: $0) }
    }

    func readUInt16(at offset: Int) -> UInt16 {
        self[offset..<(offset + 2)].reduce(0) { ($0 << 8) | UInt16($1) }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        self[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
