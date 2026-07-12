import Testing
@testable import MumbleAudio

@Test func playbackRingPreservesContinuousSampleOrder() {
    let ring = AudioSampleRingBuffer(capacity: 16)
    ring.enqueue([1, 2, 3, 4])
    var output = [Float](repeating: 0, count: 4)
    output.withUnsafeMutableBufferPointer { buffer in
        ring.render(into: buffer.baseAddress!, count: buffer.count)
    }
    #expect(output[0] > 0)
    #expect(output[0] < output[1])
    #expect(output[1] < output[2])
    #expect(output[2] < output[3])
    #expect(ring.availableSampleCount == 0)
}

@Test func playbackRingDropsOldestSamplesWhenCapacityIsExceeded() {
    let ring = AudioSampleRingBuffer(capacity: 4)
    ring.enqueue([1, 2, 3, 4, 5, 6])
    #expect(ring.availableSampleCount == 4)
    var output = [Float](repeating: 0, count: 4)
    output.withUnsafeMutableBufferPointer { buffer in
        ring.render(into: buffer.baseAddress!, count: buffer.count)
    }
    // Fade-in scales the values, but the retained sequence is still increasing.
    #expect(output[0] < output[1])
    #expect(output[1] < output[2])
    #expect(output[2] < output[3])
}

@Test func playbackRingRampsDownOnUnderflow() {
    let ring = AudioSampleRingBuffer(capacity: 8)
    ring.enqueue([Float](repeating: 1, count: 8))
    var output = [Float](repeating: 0, count: 48)
    output.withUnsafeMutableBufferPointer { buffer in
        ring.render(into: buffer.baseAddress!, count: buffer.count)
    }
    #expect(output[7] > output[20])
    #expect(output.last == 0)
}
