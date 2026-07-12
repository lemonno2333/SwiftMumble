import Foundation

public struct EncodedAudioFrame: Equatable, Sendable {
    public var frameNumber: UInt64
    public var opusData: Data

    public init(frameNumber: UInt64, opusData: Data) {
        self.frameNumber = frameNumber
        self.opusData = opusData
    }
}

public final class AudioTransmitPipeline: @unchecked Sendable {
    private let encoder: OpusEncoder
    private let lock = NSLock()
    private var nextFrameNumber: UInt64 = 0
    private let framesPerPacket: Int
    private var pendingSamples: [Float] = []

    public init(configuration: OpusEncoderConfiguration = .init(), framesPerPacket: Int = 1) throws {
        encoder = try OpusEncoder(configuration: configuration)
        self.framesPerPacket = [1, 2, 4, 6].contains(framesPerPacket) ? framesPerPacket : 1
    }

    public func enqueue10msFrame(samples: [Float]) throws -> EncodedAudioFrame? {
        lock.lock()
        defer { lock.unlock() }
        guard samples.count == 480 else { throw OpusCodecError.invalidFrameSize(samples.count) }
        pendingSamples.append(contentsOf: samples)
        guard pendingSamples.count == framesPerPacket * 480 else { return nil }
        let frame = EncodedAudioFrame(
            frameNumber: nextFrameNumber,
            opusData: try encoder.encode(samples: pendingSamples)
        )
        pendingSamples.removeAll(keepingCapacity: true)
        nextFrameNumber += UInt64(framesPerPacket)
        return frame
    }

    public func encode(samples: [Float]) throws -> EncodedAudioFrame {
        lock.lock()
        defer { lock.unlock() }

        let frame = EncodedAudioFrame(
            frameNumber: nextFrameNumber,
            opusData: try encoder.encode(samples: samples)
        )
        nextFrameNumber += 1
        return frame
    }

    public func takeTerminatorFrameNumber() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let frameNumber = nextFrameNumber
        pendingSamples.removeAll(keepingCapacity: false)
        nextFrameNumber += 1
        return frameNumber
    }
}
