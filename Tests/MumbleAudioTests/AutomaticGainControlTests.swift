import Testing
@testable import MumbleAudio

@Test func automaticGainControlRaisesQuietSignalsWithoutClipping() {
    let agc = AutomaticGainControl()
    let quiet = [Float](repeating: 0.01, count: 480)
    var output = quiet
    for _ in 0..<100 { output = agc.process(quiet) }
    #expect(output[0] > quiet[0])
    #expect(output.allSatisfy { abs($0) <= 1 })
    agc.reset()
}
