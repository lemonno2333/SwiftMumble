import Foundation

public final class AdaptiveEchoCanceller: @unchecked Sendable {
    private static let referenceCapacity = 480
    private let lock = NSLock()
    private let reference: UnsafeMutablePointer<Float>
    private var referenceCount = 0
    private var echoGain: Float = 0

    public init() {
        reference = .allocate(capacity: Self.referenceCapacity)
        reference.initialize(repeating: 0, count: Self.referenceCapacity)
    }

    deinit {
        reference.deinitialize(count: Self.referenceCapacity)
        reference.deallocate()
    }

    /// Playback is realtime-critical. A fresh echo reference is optional, so
    /// never block the mix clock while microphone processing owns this state.
    /// Copies into a preallocated buffer — no allocation on the caller's side.
    @discardableResult
    public func tryUpdateReference(pointer samples: UnsafePointer<Float>, count: Int) -> Bool {
        guard count <= Self.referenceCapacity, lock.try() else { return false }
        reference.update(from: samples, count: count)
        referenceCount = count
        lock.unlock()
        return true
    }

    @discardableResult
    public func tryUpdateReference(_ samples: [Float]) -> Bool {
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return tryUpdateReference(pointer: base, count: buffer.count)
        }
    }

    public func process(_ microphone: [Float]) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        guard referenceCount == microphone.count, referenceCount > 0 else { return microphone }
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

    public func reset() {
        lock.lock()
        referenceCount = 0
        echoGain = 0
        lock.unlock()
    }
}
