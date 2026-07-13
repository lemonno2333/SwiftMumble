import Foundation

public final class AdaptiveEchoCanceller: @unchecked Sendable {
    private let lock = NSLock()
    private var reference: [Float] = []
    private var echoGain: Float = 0

    public init() {}
    /// Playback is realtime-critical. A fresh echo reference is optional, so
    /// never hold the mixer while microphone processing owns this state.
    @discardableResult
    public func tryUpdateReference(_ samples: [Float]) -> Bool {
        guard lock.try() else { return false }
        reference = samples
        lock.unlock()
        return true
    }
    public func process(_ microphone: [Float]) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        guard reference.count == microphone.count, !reference.isEmpty else { return microphone }
        var cross: Float = 0, referencePower: Float = 0, microphonePower: Float = 0
        for i in microphone.indices {
            cross += microphone[i] * reference[i]
            referencePower += reference[i] * reference[i]
            microphonePower += microphone[i] * microphone[i]
        }
        guard referencePower > 1e-6, microphonePower > 1e-6 else { return microphone }
        let correlation = abs(cross) / sqrt(referencePower * microphonePower)
        if correlation > 0.2 {
            let estimate = min(1.5, max(-1.5, cross / referencePower))
            echoGain += (estimate - echoGain) * 0.12
        } else { echoGain *= 0.98 }
        return microphone.indices.map { min(1, max(-1, microphone[$0] - reference[$0] * echoGain)) }
    }
    public func reset() { lock.lock(); reference = []; echoGain = 0; lock.unlock() }
}
