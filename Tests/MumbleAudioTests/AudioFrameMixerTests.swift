import Testing
@testable import MumbleAudio

@Test func mixerCombinesConcurrentSourcesAndLimitsOutputWithoutHardClipping() {
    let mixer = AudioFrameMixer(frameLength: 4)
    mixer.register(source: 1)
    mixer.register(source: 2)
    mixer.push(source: 1, samples: [0.4, -0.8, 0.7, 0.1])
    mixer.push(source: 2, samples: [0.3, -0.5, 0.7, -0.2])

    guard case .samples(let mixed) = mixer.read() else {
        Issue.record("Expected a mixed audio frame")
        return
    }
    let expected: [Float] = [0.49, -0.91, 0.98, -0.07]
    #expect(zip(mixed, expected).allSatisfy { abs($0 - $1) < 0.000_001 })
}

@Test func mixerKeepsRealtimeLatencyByDroppingOldestQueuedFrame() {
    let mixer = AudioFrameMixer(frameLength: 1, maximumQueuedFramesPerSource: 2)
    mixer.register(source: 7)
    mixer.push(source: 7, samples: [0.1])
    mixer.push(source: 7, samples: [0.2])
    mixer.push(source: 7, samples: [0.3])

    #expect(mixer.droppedFrameCount == 1)
    #expect(mixer.read() == .samples([0.2]))
    #expect(mixer.read() == .samples([0.3]))
    mixer.unregister(source: 7)
    #expect(mixer.read() == .inactive)
}

@Test func mixerAppliesPerSourceGain() {
    let mixer = AudioFrameMixer(frameLength: 2)
    mixer.register(source: 1)
    mixer.setGain(0.5, source: 1)
    mixer.push(source: 1, samples: [0.4, -0.6])

    #expect(mixer.read() == .samples([0.2, -0.3]))
}

@Test func mixerClampsGainToSafeRange() {
    let mixer = AudioFrameMixer(frameLength: 1)
    mixer.register(source: 1)
    mixer.setGain(100, source: 1)
    mixer.push(source: 1, samples: [0.5])

    // Gain clamps to 3, then the frame limiter reduces the 1.5 peak to 0.98.
    #expect(mixer.read() == .samples([0.98]))
}

@Test func mixerLimiterRecoversGraduallyAfterConcurrentPeak() {
    let mixer = AudioFrameMixer(frameLength: 1)
    mixer.register(source: 1)
    mixer.register(source: 2)
    mixer.push(source: 1, samples: [1])
    mixer.push(source: 2, samples: [0.5])
    #expect(mixer.read() == .samples([0.98]))

    mixer.push(source: 1, samples: [0.5])
    guard case .samples(let recovering) = mixer.read() else {
        Issue.record("Expected a limiter recovery frame")
        return
    }
    #expect(recovering[0] > 0.32)
    #expect(recovering[0] < 0.5)
}

@Test func mixerExcludesMutedSourceButKeepsOthers() {
    let mixer = AudioFrameMixer(frameLength: 2)
    mixer.register(source: 1)
    mixer.register(source: 2)
    mixer.setMuted(true, source: 1)
    mixer.push(source: 1, samples: [0.5, 0.5])
    mixer.push(source: 2, samples: [0.2, -0.2])

    #expect(mixer.read() == .samples([0.2, -0.2]))
}

@Test func mixerDrainsMutedSourceQueue() {
    let mixer = AudioFrameMixer(frameLength: 1)
    mixer.register(source: 1)
    mixer.setMuted(true, source: 1)
    mixer.push(source: 1, samples: [0.5])
    mixer.push(source: 1, samples: [0.6])

    // First read drains one muted frame and produces silence.
    #expect(mixer.read() == .samples([0]))
    // Unmuting reveals the still-queued second frame, proving it was not stalled.
    mixer.setMuted(false, source: 1)
    #expect(mixer.read() == .samples([0.6]))
}

@Test func mixerUnregisterClearsGainAndMute() {
    let mixer = AudioFrameMixer(frameLength: 1)
    mixer.register(source: 1)
    mixer.setGain(0.25, source: 1)
    mixer.setMuted(true, source: 1)
    mixer.unregister(source: 1)

    // Re-registering the same session id starts from unity, unmuted defaults.
    mixer.register(source: 1)
    mixer.push(source: 1, samples: [0.4])
    #expect(mixer.read() == .samples([0.4]))
}

@Test func mixerAppliesMasterOutputGain() {
    let mixer = AudioFrameMixer(frameLength: 2)
    mixer.register(source: 1)
    mixer.setMasterGain(0.5)
    mixer.push(source: 1, samples: [0.8, -0.4])

    #expect(mixer.read() == .samples([0.4, -0.2]))
}

@Test func mixerDucksOutputOnlyWhileActive() {
    let mixer = AudioFrameMixer(frameLength: 1)
    mixer.register(source: 1)
    mixer.setDuckingGain(0.25)
    mixer.setDuckingActive(true)
    mixer.push(source: 1, samples: [0.8])
    #expect(mixer.read() == .samples([0.2]))

    mixer.setDuckingActive(false)
    mixer.push(source: 1, samples: [0.8])
    #expect(mixer.read() == .samples([0.8]))
}

@Test func mixerCombinesMasterAndDuckingGainsBeforeClipping() {
    let mixer = AudioFrameMixer(frameLength: 1)
    mixer.register(source: 1)
    mixer.setMasterGain(1.5)
    mixer.setDuckingGain(0.5)
    mixer.setDuckingActive(true)
    mixer.push(source: 1, samples: [0.8])

    #expect(abs((mixer.read().samplesValue?.first ?? 0) - 0.6) < 0.000_001)
}

private extension AudioFrameMixerRead {
    var samplesValue: [Float]? {
        if case .samples(let samples) = self { return samples }
        return nil
    }
}
