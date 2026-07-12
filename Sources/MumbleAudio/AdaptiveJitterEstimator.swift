import Foundation

public struct AdaptiveJitterEstimator: Equatable, Sendable {
    public let frameDuration: TimeInterval
    public let baseDelayFrames: Int
    public let minimumDelayFrames: Int
    public let maximumDelayFrames: Int

    public private(set) var estimatedJitter: TimeInterval = 0
    public private(set) var targetDelayFrames: Int

    private var previousTransit: TimeInterval?
    private var lossPenaltyFrames = 0
    private var stableFrameCount = 0

    public init(
        frameDuration: TimeInterval = 0.01,
        baseDelayFrames: Int = 3,
        minimumDelayFrames: Int = 2,
        maximumDelayFrames: Int = 10
    ) {
        precondition(frameDuration > 0)
        precondition(minimumDelayFrames >= 1)
        precondition(baseDelayFrames >= minimumDelayFrames)
        precondition(maximumDelayFrames >= baseDelayFrames)
        self.frameDuration = frameDuration
        self.baseDelayFrames = baseDelayFrames
        self.minimumDelayFrames = minimumDelayFrames
        self.maximumDelayFrames = maximumDelayFrames
        targetDelayFrames = baseDelayFrames
    }

    @discardableResult
    public mutating func observe(frameNumber: UInt64, arrivalTime: TimeInterval) -> Int {
        let transit = arrivalTime - Double(frameNumber) * frameDuration
        if let previousTransit {
            let deviation = abs(transit - previousTransit)
            estimatedJitter += (deviation - estimatedJitter) / 16
        }
        self.previousTransit = transit
        stableFrameCount += 1
        if stableFrameCount >= 100, lossPenaltyFrames > 0 {
            lossPenaltyFrames -= 1
            stableFrameCount = 0
        }
        updateTarget()
        return targetDelayFrames
    }

    @discardableResult
    public mutating func reportMissingFrame() -> Int {
        lossPenaltyFrames = min(lossPenaltyFrames + 1, 3)
        stableFrameCount = 0
        updateTarget()
        return targetDelayFrames
    }

    private mutating func updateTarget() {
        let jitterFrames = Int(ceil(estimatedJitter / frameDuration))
        targetDelayFrames = min(
            maximumDelayFrames,
            max(minimumDelayFrames, baseDelayFrames + jitterFrames + lossPenaltyFrames)
        )
    }
}
