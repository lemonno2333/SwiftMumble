import Foundation

public enum RealtimeTransmissionMode: Sendable {
    case voiceActivity
    case continuous
}

public struct RealtimeVoiceDecision: Sendable {
    public var smoothedLevelDB: Double
    public var noiseFloorDB: Double?
    public var shouldSend: Bool
    public var didChange: Bool
}

public final class RealtimeVoiceActivityProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var gate = VoiceActivityGate()
    private var smoother = LevelSmoother()
    private var noiseFloor = NoiseFloorTracker()
    private var mode: RealtimeTransmissionMode = .voiceActivity
    private var thresholdDB = -35.0
    private var lastDecision = false
    private var transmissionAllowed = false

    public init() {}

    public func configure(mode: RealtimeTransmissionMode, thresholdDB: Double) {
        lock.withLock {
            self.mode = mode
            self.thresholdDB = min(-5, max(-70, thresholdDB))
        }
    }

    public func process(levelDB: Double) -> RealtimeVoiceDecision {
        lock.withLock {
            let smoothed = smoother.process(levelDB: levelDB)
            let shouldSend: Bool
            var observedFloor: Double?
            switch mode {
            case .voiceActivity:
                shouldSend = gate.process(levelDB: smoothed, thresholdDB: thresholdDB)
                if !shouldSend { observedFloor = noiseFloor.observeSilence(levelDB: smoothed) }
            case .continuous:
                shouldSend = true
            }
            let effectiveDecision = transmissionAllowed && shouldSend
            let changed = effectiveDecision != lastDecision
            lastDecision = effectiveDecision
            return RealtimeVoiceDecision(
                smoothedLevelDB: smoothed,
                noiseFloorDB: observedFloor,
                shouldSend: effectiveDecision,
                didChange: changed
            )
        }
    }

    public func setTransmissionAllowed(_ allowed: Bool) {
        lock.withLock {
            transmissionAllowed = allowed
            if !allowed { lastDecision = false }
        }
    }

    public func reset() {
        lock.withLock {
            gate.reset()
            smoother.reset()
            noiseFloor.reset()
            lastDecision = false
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
