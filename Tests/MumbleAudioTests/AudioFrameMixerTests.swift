import Testing
@testable import MumbleAudio

private func mixOneFrame(
    _ mixer: AudioFrameMixer,
    frameLength: Int,
    sources: [(UInt32, [Float])]
) -> [Float] {
    mixer.beginFrame()
    for (source, samples) in sources {
        samples.withUnsafeBufferPointer { buffer in
            mixer.accumulate(source: source, samples: buffer.baseAddress!)
        }
    }
    var output = [Float](repeating: 0, count: frameLength)
    output.withUnsafeMutableBufferPointer { buffer in
        mixer.finalizeFrame(into: buffer.baseAddress!)
    }
    return output
}

@Test func mixerCombinesConcurrentSourcesAndLimitsOutputWithoutHardClipping() {
    let mixer = AudioFrameMixer(frameLength: 4)
    let mixed = mixOneFrame(mixer, frameLength: 4, sources: [
        (1, [0.4, -0.8, 0.7, 0.1]),
        (2, [0.3, -0.5, 0.7, -0.2]),
    ])
    let expected: [Float] = [0.49, -0.91, 0.98, -0.07]
    #expect(zip(mixed, expected).allSatisfy { abs($0 - $1) < 0.000_001 })
}

@Test func mixerReportsContributingSourceCount() {
    let mixer = AudioFrameMixer(frameLength: 1)
    mixer.beginFrame()
    let samples: [Float] = [0.1]
    samples.withUnsafeBufferPointer { mixer.accumulate(source: 1, samples: $0.baseAddress!) }
    samples.withUnsafeBufferPointer { mixer.accumulate(source: 2, samples: $0.baseAddress!) }
    var output: [Float] = [0]
    let contributors = output.withUnsafeMutableBufferPointer {
        mixer.finalizeFrame(into: $0.baseAddress!)
    }
    #expect(contributors == 2)
}

@Test func mixerAppliesPerSourceGain() {
    let mixer = AudioFrameMixer(frameLength: 2)
    mixer.setGain(0.5, source: 1)
    let mixed = mixOneFrame(mixer, frameLength: 2, sources: [(1, [0.4, -0.6])])
    #expect(zip(mixed, [0.2, -0.3] as [Float]).allSatisfy { abs($0 - $1) < 0.000_001 })
}

@Test func mixerClampsGainToSafeRange() {
    let mixer = AudioFrameMixer(frameLength: 1)
    mixer.setGain(100, source: 1)
    // Gain clamps to 3, then the frame limiter reduces the 1.5 peak to 0.98.
    let mixed = mixOneFrame(mixer, frameLength: 1, sources: [(1, [0.5])])
    #expect(abs(mixed[0] - 0.98) < 0.000_001)
}

@Test func mixerLimiterRecoversGraduallyAfterConcurrentPeak() {
    let mixer = AudioFrameMixer(frameLength: 1)
    let peaked = mixOneFrame(mixer, frameLength: 1, sources: [(1, [1]), (2, [0.5])])
    #expect(abs(peaked[0] - 0.98) < 0.000_001)

    let recovering = mixOneFrame(mixer, frameLength: 1, sources: [(1, [0.5])])
    #expect(recovering[0] > 0.32)
    #expect(recovering[0] < 0.5)
}

@Test func mixerExcludesMutedSourceButKeepsOthers() {
    let mixer = AudioFrameMixer(frameLength: 2)
    mixer.setMuted(true, source: 1)
    let mixed = mixOneFrame(mixer, frameLength: 2, sources: [
        (1, [0.5, 0.5]),
        (2, [0.2, -0.2]),
    ])
    #expect(zip(mixed, [0.2, -0.2] as [Float]).allSatisfy { abs($0 - $1) < 0.000_001 })
}

@Test func mixerUnregisterClearsGainAndMute() {
    let mixer = AudioFrameMixer(frameLength: 1)
    mixer.setGain(0.25, source: 1)
    mixer.setMuted(true, source: 1)
    mixer.unregister(source: 1)

    // Re-registering the same session id starts from unity, unmuted defaults.
    mixer.register(source: 1)
    let mixed = mixOneFrame(mixer, frameLength: 1, sources: [(1, [0.4])])
    #expect(abs(mixed[0] - 0.4) < 0.000_001)
}

@Test func mixerAppliesMasterOutputGain() {
    let mixer = AudioFrameMixer(frameLength: 2)
    mixer.setMasterGain(0.5)
    let mixed = mixOneFrame(mixer, frameLength: 2, sources: [(1, [0.8, -0.4])])
    #expect(zip(mixed, [0.4, -0.2] as [Float]).allSatisfy { abs($0 - $1) < 0.000_001 })
}

@Test func mixerDucksOutputOnlyWhileActive() {
    let mixer = AudioFrameMixer(frameLength: 1)
    mixer.setDuckingGain(0.25)
    mixer.setDuckingActive(true)
    let ducked = mixOneFrame(mixer, frameLength: 1, sources: [(1, [0.8])])
    #expect(abs(ducked[0] - 0.2) < 0.000_001)

    mixer.setDuckingActive(false)
    let restored = mixOneFrame(mixer, frameLength: 1, sources: [(1, [0.8])])
    #expect(abs(restored[0] - 0.8) < 0.000_001)
}

@Test func mixerCombinesMasterAndDuckingGainsBeforeClipping() {
    let mixer = AudioFrameMixer(frameLength: 1)
    mixer.setMasterGain(1.5)
    mixer.setDuckingGain(0.5)
    mixer.setDuckingActive(true)
    let mixed = mixOneFrame(mixer, frameLength: 1, sources: [(1, [0.8])])
    #expect(abs(mixed[0] - 0.6) < 0.000_001)
}
