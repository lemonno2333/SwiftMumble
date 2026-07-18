import Testing
@testable import MumbleAudio

@Test func adaptiveJitterEstimatorStaysLowForStableArrivals() {
    var estimator = AdaptiveJitterEstimator(baseDelayFrames: 3)
    for frame in 0..<200 {
        estimator.observe(frameNumber: UInt64(frame), arrivalTime: Double(frame) * 0.01 + 5)
    }

    #expect(estimator.targetDelayFrames == 3)
    #expect(estimator.estimatedJitter < 0.000_001)
}

@Test func adaptiveJitterEstimatorIgnoresSpeechGaps() {
    var estimator = AdaptiveJitterEstimator(baseDelayFrames: 3)
    for frame in 0..<50 {
        estimator.observe(frameNumber: UInt64(frame), arrivalTime: Double(frame) * 0.01 + 5)
    }
    // The sender destroys its transmit pipeline at end-of-utterance and starts
    // the next talkspurt from frame 0. Two seconds of real-world silence pass
    // in between. The estimator must recognise this as a baseline shift, not a
    // two-second jitter spike, otherwise the target delay balloons right when
    // the next utterance begins.
    let resumeTime = 5 + 49 * 0.01 + 2.0
    for frame in 0..<50 {
        estimator.observe(
            frameNumber: UInt64(frame),
            arrivalTime: resumeTime + Double(frame) * 0.01
        )
    }

    #expect(estimator.targetDelayFrames == 3)
    #expect(estimator.estimatedJitter < 0.001)
}

@Test func adaptiveJitterEstimatorRaisesDelayForBurstsAndLoss() {
    var estimator = AdaptiveJitterEstimator(baseDelayFrames: 3)
    estimator.observe(frameNumber: 0, arrivalTime: 10)
    for frame in 1...20 {
        let burst = frame.isMultiple(of: 2) ? 0.04 : 0
        estimator.observe(
            frameNumber: UInt64(frame),
            arrivalTime: 10 + Double(frame) * 0.01 + burst
        )
    }
    let burstTarget = estimator.targetDelayFrames
    estimator.reportMissingFrame()

    #expect(burstTarget > 3)
    #expect(estimator.targetDelayFrames > burstTarget)
    #expect(estimator.targetDelayFrames <= 10)
}
