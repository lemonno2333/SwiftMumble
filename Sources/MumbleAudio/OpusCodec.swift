import COpus
import COpusShim
import Foundation

public enum OpusCodecError: Error, Equatable {
    case initializationFailed(code: Int32)
    case encodingFailed(code: Int32)
    case decodingFailed(code: Int32)
    case invalidFrameSize(Int)
    case configurationFailed(code: Int32)
}

public struct OpusEncoderConfiguration: Equatable, Sendable {
    public var bitrate: Int32
    public var complexity: Int32
    public var expectedPacketLossPercent: Int32
    public var inbandFEC: Bool
    public var lowLatency: Bool

    public init(
        bitrate: Int32 = 40_000,
        complexity: Int32 = 8,
        expectedPacketLossPercent: Int32 = 5,
        inbandFEC: Bool = true,
        lowLatency: Bool = false
    ) {
        self.bitrate = min(128_000, max(12_000, bitrate))
        self.complexity = min(10, max(0, complexity))
        self.expectedPacketLossPercent = min(30, max(0, expectedPacketLossPercent))
        self.inbandFEC = inbandFEC
        self.lowLatency = lowLatency
    }
}

public final class OpusEncoder: @unchecked Sendable {
    public static let sampleRate: Int32 = 48_000
    public static let channels: Int32 = 1
    public static let maximumPacketSize = 4_000

    private let encoder: OpaquePointer

    public let configuration: OpusEncoderConfiguration

    public init(configuration: OpusEncoderConfiguration = .init()) throws {
        self.configuration = configuration
        var error: Int32 = 0
        guard let encoder = opus_encoder_create(
            Self.sampleRate,
            Self.channels,
            2_048,
            &error
        ), error == OPUS_OK else {
            throw OpusCodecError.initializationFailed(code: error)
        }
        let configureResult = nm_opus_configure_encoder(
            encoder,
            configuration.bitrate,
            configuration.complexity,
            configuration.expectedPacketLossPercent,
            configuration.inbandFEC ? 1 : 0,
            configuration.lowLatency ? 1 : 0
        )
        guard configureResult == OPUS_OK else {
            opus_encoder_destroy(encoder)
            throw OpusCodecError.configurationFailed(code: configureResult)
        }
        self.encoder = encoder
    }

    deinit {
        opus_encoder_destroy(encoder)
    }

    public func encode(samples: [Float]) throws -> Data {
        guard Self.validFrameSizes.contains(samples.count) else {
            throw OpusCodecError.invalidFrameSize(samples.count)
        }

        var packet = [UInt8](repeating: 0, count: Self.maximumPacketSize)
        let encodedLength = samples.withUnsafeBufferPointer { sampleBuffer in
            packet.withUnsafeMutableBufferPointer { packetBuffer in
                opus_encode_float(
                    encoder,
                    sampleBuffer.baseAddress!,
                    Int32(samples.count),
                    packetBuffer.baseAddress!,
                    Int32(Self.maximumPacketSize)
                )
            }
        }

        guard encodedLength >= 0 else {
            throw OpusCodecError.encodingFailed(code: encodedLength)
        }
        return Data(packet.prefix(Int(encodedLength)))
    }

    private static let validFrameSizes: Set<Int> = [120, 240, 480, 960, 1_920, 2_880]
}

public final class OpusDecoder: @unchecked Sendable {
    private let decoder: OpaquePointer

    public init() throws {
        var error: Int32 = 0
        guard let decoder = opus_decoder_create(
            OpusEncoder.sampleRate,
            OpusEncoder.channels,
            &error
        ), error == OPUS_OK else {
            throw OpusCodecError.initializationFailed(code: error)
        }
        self.decoder = decoder
    }

    deinit {
        opus_decoder_destroy(decoder)
    }

    public func decode(packet: Data, maximumFrameSize: Int = 5_760) throws -> [Float] {
        var samples = [Float](repeating: 0, count: maximumFrameSize)
        let decodedSamples = try samples.withUnsafeMutableBufferPointer { sampleBuffer in
            try decode(packet: packet, into: sampleBuffer.baseAddress!, capacity: maximumFrameSize)
        }
        return Array(samples.prefix(decodedSamples))
    }

    /// Allocation-free variant for the realtime mix path: decodes into a
    /// caller-owned scratch buffer and returns the produced sample count.
    public func decode(
        packet: Data,
        into output: UnsafeMutablePointer<Float>,
        capacity: Int
    ) throws -> Int {
        let decodedSamples = packet.withUnsafeBytes { packetBuffer in
            opus_decode_float(
                decoder,
                packetBuffer.bindMemory(to: UInt8.self).baseAddress,
                Int32(packet.count),
                output,
                Int32(capacity),
                0
            )
        }
        guard decodedSamples >= 0 else {
            throw OpusCodecError.decodingFailed(code: decodedSamples)
        }
        return Int(decodedSamples)
    }

    public func decodeMissing(frameSize: Int = 480) throws -> [Float] {
        var samples = [Float](repeating: 0, count: frameSize)
        let decodedSamples = try samples.withUnsafeMutableBufferPointer { sampleBuffer in
            try decodeMissing(into: sampleBuffer.baseAddress!, frameSize: frameSize)
        }
        return Array(samples.prefix(decodedSamples))
    }

    /// Allocation-free packet-loss concealment into a caller-owned buffer.
    public func decodeMissing(
        into output: UnsafeMutablePointer<Float>,
        frameSize: Int = 480
    ) throws -> Int {
        let decodedSamples = opus_decode_float(
            decoder,
            nil,
            0,
            output,
            Int32(frameSize),
            0
        )
        guard decodedSamples >= 0 else {
            throw OpusCodecError.decodingFailed(code: decodedSamples)
        }
        return Int(decodedSamples)
    }
}
