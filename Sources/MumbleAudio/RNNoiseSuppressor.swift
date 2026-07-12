import CRNNoise
import Foundation

public final class RNNoiseSuppressor: @unchecked Sendable {
    public static let frameLength = 480
    private let lock = NSLock()
    private var state: OpaquePointer?

    public init() {
        state = rnnoise_create(nil)
    }

    deinit {
        if let state { rnnoise_destroy(state) }
    }

    public func process(_ samples: [Float]) -> [Float] {
        guard samples.count == Self.frameLength, let state else { return samples }
        return lock.withLock {
            var input = samples.map { min(1, max(-1, $0)) * 32_768 }
            var output = [Float](repeating: 0, count: Self.frameLength)
            rnnoise_process_frame(state, &output, &input)
            return output.map { min(1, max(-1, $0 / 32_768)) }
        }
    }

    public func reset() {
        lock.withLock {
            if let state { rnnoise_destroy(state) }
            state = rnnoise_create(nil)
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
