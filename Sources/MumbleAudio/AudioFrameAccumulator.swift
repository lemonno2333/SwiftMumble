import Foundation

public struct AudioFrameAccumulator: Sendable {
    public let frameSize: Int
    private var pending: [Float] = []

    public init(frameSize: Int = 480) {
        precondition(frameSize > 0)
        self.frameSize = frameSize
    }

    public mutating func append(_ samples: [Float]) -> [[Float]] {
        pending.append(contentsOf: samples)
        var frames: [[Float]] = []

        while pending.count >= frameSize {
            frames.append(Array(pending.prefix(frameSize)))
            pending.removeFirst(frameSize)
        }

        return frames
    }

    public mutating func reset() {
        pending.removeAll(keepingCapacity: true)
    }
}
