import Foundation

/// Gain staging and limiting for the 10 ms mix tick.
///
/// The mix clock owns the frame cadence: it calls `beginFrame()`, then
/// `accumulate(source:samples:)` once per speaker that produced audio this
/// tick, then `finalizeFrame(into:)`. The mixer holds no queues — per-speaker
/// buffering lives in each `AudioReceivePipeline`'s jitter buffer, which is
/// where late frames can still be concealed correctly.
///
/// Configuration setters (gain, mute, ducking, master volume) are safe to call
/// from any thread; the mix-path methods must only be called from the single
/// mix clock thread.
public final class AudioFrameMixer: @unchecked Sendable {
    private let lock = NSLock()
    private let frameLength: Int
    private var gains: [UInt32: Float] = [:]
    private var mutedSources: Set<UInt32> = []
    private var masterGain: Float = 1
    private var duckingGain: Float = 0.35
    private var isDucking = false
    private var limiterGain: Float = 1

    private let accumulator: UnsafeMutablePointer<Float>
    private var accumulatedSources = 0

    public init(frameLength: Int = 480) {
        precondition(frameLength > 0)
        self.frameLength = frameLength
        accumulator = .allocate(capacity: frameLength)
        accumulator.initialize(repeating: 0, count: frameLength)
    }

    deinit {
        accumulator.deinitialize(count: frameLength)
        accumulator.deallocate()
    }

    public func register(source: UInt32) {
        // Sources start at unity gain, unmuted; nothing to prepare.
    }

    public func unregister(source: UInt32) {
        lock.withLock {
            gains.removeValue(forKey: source)
            mutedSources.remove(source)
        }
    }

    public func removeAllSources() {
        lock.withLock {
            gains.removeAll()
            mutedSources.removeAll()
            limiterGain = 1
        }
    }

    /// Per-user playback gain. 1 is unity; values above 1 amplify. Clamped to a
    /// safe range so a single source cannot dominate or invert the mix.
    public func setGain(_ gain: Float, source: UInt32) {
        lock.withLock { gains[source] = min(3, max(0, gain)) }
    }

    public func setMuted(_ muted: Bool, source: UInt32) {
        lock.withLock {
            if muted { mutedSources.insert(source) } else { mutedSources.remove(source) }
        }
    }

    public func setMasterGain(_ gain: Float) {
        lock.withLock { masterGain = min(2, max(0, gain)) }
    }

    public func setDuckingGain(_ gain: Float) {
        lock.withLock { duckingGain = min(1, max(0, gain)) }
    }

    public func setDuckingActive(_ active: Bool) {
        lock.withLock { isDucking = active }
    }

    // MARK: - Mix path (single mix-clock thread only)

    public func beginFrame() {
        accumulator.update(repeating: 0, count: frameLength)
        accumulatedSources = 0
    }

    /// Adds one speaker's frame (exactly `frameLength` samples) into the
    /// accumulator with that speaker's gain. Muted sources are skipped.
    public func accumulate(source: UInt32, samples: UnsafePointer<Float>) {
        let configuration = lock.withLock { (mutedSources.contains(source), gains[source] ?? 1) }
        guard !configuration.0 else { return }
        let gain = configuration.1
        if gain == 1 {
            for index in 0..<frameLength { accumulator[index] += samples[index] }
        } else {
            guard gain > 0 else { return }
            for index in 0..<frameLength { accumulator[index] += samples[index] * gain }
        }
        accumulatedSources += 1
    }

    /// Applies master gain, ducking, and the smoothed limiter, writing the
    /// final frame into `output` (capacity at least `frameLength`). Returns the
    /// number of sources that contributed since `beginFrame()`.
    @discardableResult
    public func finalizeFrame(into output: UnsafeMutablePointer<Float>) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let outputGain = masterGain * (isDucking ? duckingGain : 1)
        var peak: Float = 0
        for index in 0..<frameLength {
            let sample = accumulator[index] * outputGain
            accumulator[index] = sample
            peak = max(peak, abs(sample))
        }
        let targetGain: Float = peak > 0.98 ? 0.98 / peak : 1
        if targetGain < limiterGain {
            limiterGain = targetGain
        } else {
            limiterGain += (targetGain - limiterGain) * 0.05
        }
        for index in 0..<frameLength {
            output[index] = min(0.98, max(-0.98, accumulator[index] * limiterGain))
        }
        return accumulatedSources
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return body()
    }
}
