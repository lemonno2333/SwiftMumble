import Foundation

public final class AutomaticGainControl: @unchecked Sendable {
    private let lock = NSLock()
    private var gain: Float = 1

    public init() {}

    public func process(_ samples: [Float], targetDB: Float = -18, maximumGain: Float = 8) -> [Float] {
        guard !samples.isEmpty else { return samples }
        lock.lock(); defer { lock.unlock() }
        let power = samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count)
        let rms = sqrt(max(power, 1e-12))
        let target = pow(10, targetDB / 20)
        let desired = min(maximumGain, max(0.25, target / rms))
        let smoothing: Float = desired < gain ? 0.25 : 0.025
        gain += (desired - gain) * smoothing
        return samples.map { min(1, max(-1, $0 * gain)) }
    }

    public func reset() { lock.lock(); gain = 1; lock.unlock() }
}
