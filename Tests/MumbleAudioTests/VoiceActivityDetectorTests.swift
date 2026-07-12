import Testing
@testable import MumbleAudio

@Test func audioLevelMeterReportsKnownRMSLevels() {
    #expect(abs(AudioLevelMeter.decibels(samples: [1, 1, 1]) - 0) < 0.001)
    #expect(abs(AudioLevelMeter.decibels(samples: [0.1, 0.1, 0.1]) + 20) < 0.001)
    #expect(AudioLevelMeter.decibels(samples: [0, 0, 0]) == -80)
}

@Test func voiceActivityGateKeepsSentenceTailOpen() {
    var gate = VoiceActivityGate(hangoverFrames: 2)

    let voice = gate.process(levelDB: -20, thresholdDB: -35)
    let tailOne = gate.process(levelDB: -60, thresholdDB: -35)
    let tailTwo = gate.process(levelDB: -60, thresholdDB: -35)
    let closed = gate.process(levelDB: -60, thresholdDB: -35)

    #expect(voice)
    #expect(tailOne)
    #expect(tailTwo)
    #expect(!closed)
}

@Test func levelSmootherAdoptsFirstSampleThenEases() {
    var smoother = LevelSmoother(attack: 0.5, release: 0.25)

    #expect(smoother.process(levelDB: -40) == -40)
    // Rising uses the faster attack coefficient: -40 + (-20 - -40) * 0.5.
    #expect(abs(smoother.process(levelDB: -20) - -30) < 0.000_001)
    // Falling uses the slower release coefficient: -30 + (-70 - -30) * 0.25.
    #expect(abs(smoother.process(levelDB: -70) - -40) < 0.000_001)
}

@Test func noiseFloorTrackerFallsFastAndRisesSlow() {
    var tracker = NoiseFloorTracker(
        marginDB: 10,
        fallCoefficient: 0.5,
        riseCoefficient: 0.1,
        initialFloorDB: -40
    )

    // First silence sample is adopted directly.
    #expect(tracker.observeSilence(levelDB: -50) == -50)
    // A quieter sample pulls the floor down quickly: -50 + (-60 - -50) * 0.5.
    #expect(abs(tracker.observeSilence(levelDB: -60) - -55) < 0.000_001)
    // A louder sample nudges it up only slightly: -55 + (-45 - -55) * 0.1.
    #expect(abs(tracker.observeSilence(levelDB: -45) - -54) < 0.000_001)
}

@Test func noiseFloorTrackerRecommendsThresholdAboveFloor() {
    var tracker = NoiseFloorTracker(marginDB: 12, initialFloorDB: -55)
    tracker.observeSilence(levelDB: -55)

    #expect(abs(tracker.recommendedThresholdDB - -43) < 0.000_001)
}

@Test func noiseFloorTrackerClampsRecommendationToSliderRange() {
    var tracker = NoiseFloorTracker(marginDB: 30, initialFloorDB: -20)
    tracker.observeSilence(levelDB: -20)

    // -20 + 30 = 10 would exceed the slider max, so it clamps to -5.
    #expect(tracker.recommendedThresholdDB == -5)
}
