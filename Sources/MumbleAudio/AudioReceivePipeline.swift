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

/// Pull-driven per-speaker receive pipeline.
///
/// The mix clock calls `pull(into:)` once per 10 ms tick. A frame that is due
/// but not yet arrived is concealed with Opus PLC *and its slot is skipped*,
/// so a late packet is dropped on arrival instead of permanently growing this
/// speaker's latency. A run of consecutive concealments ends the talk spurt,
/// which resets the jitter buffer for a fresh warm-up on the next spurt.
public final class AudioReceivePipeline: @unchecked Sendable {
    public static let frameLength = 480

    private let lock = NSLock()
    private let decoder: OpusDecoder
    private var jitterBuffer: AudioJitterBuffer<BufferedAudioPacket>
    private var jitterEstimator: AdaptiveJitterEstimator
    private let maximumConsecutiveConcealedFrames: Int

    // Decoded packet samples beyond the first frame stay in this scratch and
    // are served on subsequent pulls. Steady state allocates nothing.
    private let scratchCapacity = 5_760
    private let scratch: UnsafeMutablePointer<Float>
    private var scratchCount = 0
    private var scratchOffset = 0

    private var isInSpurt = false
    private var consecutiveConcealedFrames = 0
    private var totalConcealedFrames: UInt64 = 0

    public init(targetDelayFrames: Int = 3, maximumConsecutiveConcealedFrames: Int = 10) throws {
        precondition(maximumConsecutiveConcealedFrames >= 1)
        decoder = try OpusDecoder()
        jitterBuffer = AudioJitterBuffer(targetDelayFrames: targetDelayFrames)
        jitterEstimator = AdaptiveJitterEstimator(
            baseDelayFrames: targetDelayFrames,
            minimumDelayFrames: min(2, targetDelayFrames),
            maximumDelayFrames: max(10, targetDelayFrames)
        )
        self.maximumConsecutiveConcealedFrames = maximumConsecutiveConcealedFrames
        scratch = .allocate(capacity: scratchCapacity)
        scratch.initialize(repeating: 0, count: scratchCapacity)
    }

    deinit {
        scratch.deinitialize(count: scratchCapacity)
        scratch.deallocate()
    }

    public var targetDelayFrames: Int {
        lock.withLock { jitterEstimator.targetDelayFrames }
    }

    public var estimatedJitterMilliseconds: Double {
        lock.withLock { jitterEstimator.estimatedJitter * 1_000 }
    }

    /// Total frames produced by concealment instead of decoded audio. The
    /// multi-speaker stress check uses this as its primary health metric.
    public var concealedFrameCount: UInt64 {
        lock.withLock { totalConcealedFrames }
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

    /// Produces exactly one 10 ms frame into `output` (capacity must be at
    /// least `frameLength`) and returns `true`, or returns `false` when the
    /// source is idle: still warming up, terminated, or timed out.
    public func pull(into output: UnsafeMutablePointer<Float>) -> Bool {
        lock.withLock {
            if scratchOffset < scratchCount {
                output.update(from: scratch + scratchOffset, count: Self.frameLength)
                scratchOffset += Self.frameLength
                return true
            }

            switch jitterBuffer.read() {
            case .waiting:
                guard isInSpurt else { return false }
                // The next frame is due but has not arrived. Conceal it and
                // skip its slot so the late packet cannot add permanent delay.
                jitterBuffer.advanceExpectedFrameNumber(by: 1)
                jitterBuffer.updateTargetDelayFrames(jitterEstimator.reportMissingFrame())
                return concealFrame(into: output)

            case .missing:
                jitterBuffer.updateTargetDelayFrames(jitterEstimator.reportMissingFrame())
                return concealFrame(into: output)

            case .packet(_, let packet):
                if packet.isTerminator {
                    endSpurt()
                    return false
                }
                do {
                    return try decodePacket(packet, into: output)
                } catch {
                    // A corrupt packet mid-spurt is indistinguishable from a
                    // lost one downstream; conceal to keep the clock steady.
                    return concealFrame(into: output)
                }
            }
        }
    }

    private func decodePacket(
        _ packet: BufferedAudioPacket,
        into output: UnsafeMutablePointer<Float>
    ) throws -> Bool {
        let decoded = try decoder.decode(
            packet: packet.opusData,
            into: scratch,
            capacity: scratchCapacity
        )
        guard decoded > 0 else { return concealFrame(into: output) }

        if packet.volume != 1 {
            for index in 0..<decoded { scratch[index] *= packet.volume }
        }
        // Pad the tail so the packet occupies whole 10 ms frames.
        let frames = (decoded + Self.frameLength - 1) / Self.frameLength
        let paddedCount = frames * Self.frameLength
        if paddedCount > decoded {
            (scratch + decoded).update(repeating: 0, count: paddedCount - decoded)
        }
        if frames > 1 {
            jitterBuffer.advanceExpectedFrameNumber(by: UInt64(frames - 1))
        }
        scratchCount = paddedCount
        scratchOffset = Self.frameLength
        output.update(from: scratch, count: Self.frameLength)
        isInSpurt = true
        consecutiveConcealedFrames = 0
        return true
    }

    private func endSpurt() {
        jitterBuffer.reset()
        scratchCount = 0
        scratchOffset = 0
        isInSpurt = false
        consecutiveConcealedFrames = 0
    }

    private func concealFrame(into output: UnsafeMutablePointer<Float>) -> Bool {
        consecutiveConcealedFrames += 1
        totalConcealedFrames &+= 1
        if consecutiveConcealedFrames > maximumConsecutiveConcealedFrames {
            endSpurt()
            return false
        }
        guard let produced = try? decoder.decodeMissing(into: output, frameSize: Self.frameLength),
              produced > 0 else {
            output.update(repeating: 0, count: Self.frameLength)
            return true
        }
        if produced < Self.frameLength {
            (output + produced).update(repeating: 0, count: Self.frameLength - produced)
        }
        return true
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
