import Foundation

public enum AudioFrameMixerRead: Equatable, Sendable {
    case inactive
    case waiting
    case samples([Float])
}

public final class AudioFrameMixer: @unchecked Sendable {
    private let lock = NSLock()
    private let frameLength: Int
    private let maximumQueuedFramesPerSource: Int
    private var queues: [UInt32: [[Float]]] = [:]
    private var gains: [UInt32: Float] = [:]
    private var mutedSources: Set<UInt32> = []
    private var masterGain: Float = 1
    private var duckingGain: Float = 0.35
    private var isDucking = false
    private var droppedFrames = 0

    public init(frameLength: Int = 480, maximumQueuedFramesPerSource: Int = 6) {
        precondition(frameLength > 0)
        precondition(maximumQueuedFramesPerSource > 0)
        self.frameLength = frameLength
        self.maximumQueuedFramesPerSource = maximumQueuedFramesPerSource
    }

    public var droppedFrameCount: Int {
        lock.withLock { droppedFrames }
    }

    public func register(source: UInt32) {
        lock.withLock {
            if queues[source] == nil { queues[source] = [] }
        }
    }

    public func unregister(source: UInt32) {
        lock.withLock {
            _ = queues.removeValue(forKey: source)
            gains.removeValue(forKey: source)
            mutedSources.remove(source)
        }
    }

    public func removeAllSources() {
        lock.withLock {
            queues.removeAll()
            gains.removeAll()
            mutedSources.removeAll()
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

    public func push(source: UInt32, samples: [Float]) {
        guard samples.count == frameLength else { return }
        lock.withLock {
            var queue = queues[source] ?? []
            if queue.count >= maximumQueuedFramesPerSource {
                queue.removeFirst()
                droppedFrames += 1
            }
            queue.append(samples)
            queues[source] = queue
        }
    }

    public func read() -> AudioFrameMixerRead {
        lock.withLock {
            guard !queues.isEmpty else { return .inactive }
            guard queues.values.contains(where: { !$0.isEmpty }) else { return .waiting }

            var mixed = [Float](repeating: 0, count: frameLength)
            for source in Array(queues.keys) {
                guard var queue = queues[source], !queue.isEmpty else { continue }
                let frame = queue.removeFirst()
                queues[source] = queue
                // Drain muted sources so their latency does not build up, but
                // keep their samples out of the mix.
                if mutedSources.contains(source) { continue }
                let gain = gains[source] ?? 1
                if gain == 1 {
                    for index in mixed.indices { mixed[index] += frame[index] }
                } else {
                    for index in mixed.indices { mixed[index] += frame[index] * gain }
                }
            }
            let outputGain = masterGain * (isDucking ? duckingGain : 1)
            for index in mixed.indices {
                mixed[index] = min(1, max(-1, mixed[index] * outputGain))
            }
            return .samples(mixed)
        }
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return body()
    }
}
