import Testing
@testable import MumbleAudio

@Test func accumulatorEmitsExactFramesAndKeepsRemainder() {
    var accumulator = AudioFrameAccumulator(frameSize: 4)

    #expect(accumulator.append([0, 1, 2]).isEmpty)
    #expect(accumulator.append([3, 4, 5, 6, 7, 8]) == [
        [0, 1, 2, 3],
        [4, 5, 6, 7]
    ])
    #expect(accumulator.append([9, 10, 11]) == [[8, 9, 10, 11]])
}
