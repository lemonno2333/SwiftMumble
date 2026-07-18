import Foundation

public final class AudioInputProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private let workLock = NSLock()
    private let processingQueue = DispatchQueue(label: "com.leo.SwiftMumble.inputProcessing", qos: .userInitiated)
    private let timeoutQueue = DispatchQueue(label: "com.leo.SwiftMumble.inputProcessingTimeout", qos: .userInitiated)
    private let echoCanceller = AdaptiveEchoCanceller()
    private let noiseSuppressor = RNNoiseSuppressor()
    private let gainControl = AutomaticGainControl()
    private var echoEnabled = false
    private var noiseEnabled = false
    private var gainEnabled = false
    private var isProcessing = false

    public init() {}

    public func configure(echo: Bool, noiseSuppression: Bool, automaticGain: Bool) {
        lock.withLock {
            echoEnabled = echo
            noiseEnabled = noiseSuppression
            gainEnabled = automaticGain
        }
    }

    public func process(_ samples: [Float]) -> [Float] {
        let configuration = lock.withLock { (echoEnabled, noiseEnabled, gainEnabled) }
        let echoReduced = configuration.0 ? echoCanceller.process(samples) : samples
        let denoised = configuration.1 ? noiseSuppressor.process(echoReduced) : echoReduced
        return configuration.2 ? gainControl.process(denoised) : denoised
    }

    /// Audio enhancement is optional; realtime delivery is not. If a native
    /// processor exceeds one 10 ms frame budget, bypass it instead of blocking
    /// VAD, the meter, and transmission indefinitely.
    public func processRealtime(_ samples: [Float], deadlineMilliseconds: Int = 8) async -> [Float] {
        let accepted = workLock.withLock {
            guard !isProcessing else { return false }
            isProcessing = true
            return true
        }
        guard accepted else { return samples }

        return await withCheckedContinuation { continuation in
            let gate = AudioProcessingCompletionGate(continuation: continuation)
            processingQueue.async { [self] in
                let result = process(samples)
                workLock.withLock { isProcessing = false }
                gate.resume(with: result)
            }
            timeoutQueue.asyncAfter(deadline: .now() + .milliseconds(max(1, deadlineMilliseconds))) {
                gate.resume(with: samples)
            }
        }
    }

    @discardableResult
    public func tryUpdatePlaybackReference(_ samples: [Float]) -> Bool {
        echoCanceller.tryUpdateReference(samples)
    }

    /// Allocation-free variant used by the mix clock.
    @discardableResult
    public func tryUpdatePlaybackReference(pointer samples: UnsafePointer<Float>, count: Int) -> Bool {
        echoCanceller.tryUpdateReference(pointer: samples, count: count)
    }

    public func resetEchoCancellation() {
        echoCanceller.reset()
    }
}

private final class AudioProcessingCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[Float], Never>?

    init(continuation: CheckedContinuation<[Float], Never>) {
        self.continuation = continuation
    }

    func resume(with samples: [Float]) {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: samples)
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return body()
    }
}
