import Foundation

public struct BufferedAudioPacket: Equatable, Sendable {
    public var opusData: Data
    public var volume: Float
    public var isTerminator: Bool

    public init(opusData: Data, volume: Float = 1, isTerminator: Bool = false) {
        self.opusData = opusData
        self.volume = volume
        self.isTerminator = isTerminator
    }
}

public enum AudioReceiveRead: Equatable, Sendable {
    case waiting
    case samples([Float])
    case finished
}

public final class AudioReceivePipeline: @unchecked Sendable {
    private let lock = NSLock()
    private let decoder: OpusDecoder
    private var jitterBuffer: AudioJitterBuffer<BufferedAudioPacket>
    private var jitterEstimator: AdaptiveJitterEstimator
    private var pendingDecodedFrames: [[Float]] = []

    public init(targetDelayFrames: Int = 3) throws {
        decoder = try OpusDecoder()
        jitterBuffer = AudioJitterBuffer(targetDelayFrames: targetDelayFrames)
        jitterEstimator = AdaptiveJitterEstimator(
            baseDelayFrames: targetDelayFrames,
            minimumDelayFrames: min(2, targetDelayFrames),
            maximumDelayFrames: max(10, targetDelayFrames)
        )
    }

    public var targetDelayFrames: Int {
        lock.withLock { jitterEstimator.targetDelayFrames }
    }

    public var estimatedJitterMilliseconds: Double {
        lock.withLock { jitterEstimator.estimatedJitter * 1_000 }
    }

    public func push(
        frameNumber: UInt64,
        packet: BufferedAudioPacket,
        arrivalTime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        lock.withLock {
            let target = jitterEstimator.observe(frameNumber: frameNumber, arrivalTime: arrivalTime)
            jitterBuffer.updateTargetDelayFrames(target)
            jitterBuffer.push(frameNumber: frameNumber, packet: packet)
        }
    }

    public func read() throws -> AudioReceiveRead {
        try lock.withLock {
            if !pendingDecodedFrames.isEmpty {
                return .samples(pendingDecodedFrames.removeFirst())
            }
            switch jitterBuffer.read() {
            case .waiting:
                return .waiting
            case .missing:
                jitterBuffer.updateTargetDelayFrames(jitterEstimator.reportMissingFrame())
                return .samples(try decoder.decodeMissing())
            case .packet(_, let packet):
                if packet.isTerminator {
                    jitterBuffer.reset()
                    pendingDecodedFrames.removeAll(keepingCapacity: true)
                    return .finished
                }
                var samples = try decoder.decode(packet: packet.opusData)
                if packet.volume != 1 {
                    for index in samples.indices { samples[index] *= packet.volume }
                }
                let frames = Self.splitIntoTenMillisecondFrames(samples)
                guard let first = frames.first else { return .waiting }
                if frames.count > 1 {
                    jitterBuffer.advanceExpectedFrameNumber(by: UInt64(frames.count - 1))
                    pendingDecodedFrames.append(contentsOf: frames.dropFirst())
                }
                return .samples(first)
            }
        }
    }

    private static func splitIntoTenMillisecondFrames(_ samples: [Float]) -> [[Float]] {
        guard !samples.isEmpty else { return [] }
        var result: [[Float]] = []
        result.reserveCapacity((samples.count + 479) / 480)
        var offset = 0
        while offset < samples.count {
            let end = min(samples.count, offset + 480)
            var frame = Array(samples[offset..<end])
            if frame.count < 480 { frame.append(contentsOf: repeatElement(0, count: 480 - frame.count)) }
            result.append(frame)
            offset = end
        }
        return result
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
