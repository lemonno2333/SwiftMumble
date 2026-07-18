import Testing
@testable import MumbleAudio

@Test func jitterBufferReordersPacketsAndReportsLoss() {
    var buffer = AudioJitterBuffer<String>(targetDelayFrames: 3)
    buffer.push(frameNumber: 10, packet: "ten")
    // One buffered frame spans less than the 3-frame target: keep waiting.
    #expect(buffer.read() == .waiting)
    buffer.push(frameNumber: 12, packet: "twelve")
    buffer.push(frameNumber: 13, packet: "thirteen")

    #expect(buffer.read() == .packet(frameNumber: 10, "ten"))
    #expect(buffer.read() == .missing(frameNumber: 11))
    #expect(buffer.read() == .packet(frameNumber: 12, "twelve"))
    #expect(buffer.read() == .packet(frameNumber: 13, "thirteen"))
    #expect(buffer.read() == .waiting)
}

@Test func jitterBufferWarmupMeasuresBufferedSpanNotPacketCount() {
    // Frame numbers advance in 10 ms units: two 20 ms packets (stride 2) span
    // 3 frame slots, which satisfies a 3-frame (30 ms) target delay.
    var buffer = AudioJitterBuffer<String>(targetDelayFrames: 3)
    buffer.push(frameNumber: 0, packet: "first")
    #expect(buffer.read() == .waiting)
    buffer.push(frameNumber: 2, packet: "second")
    #expect(buffer.read() == .packet(frameNumber: 0, "first"))
}

@Test func jitterBufferCanAdvanceAcrossMultiFramePacket() {
    var buffer = AudioJitterBuffer<String>(targetDelayFrames: 2)
    buffer.push(frameNumber: 0, packet: "zero")
    buffer.push(frameNumber: 2, packet: "two")
    #expect(buffer.read() == .packet(frameNumber: 0, "zero"))
    buffer.advanceExpectedFrameNumber(by: 1)
    #expect(buffer.read() == .packet(frameNumber: 2, "two"))
}

@Test func jitterBufferIgnoresLateAndDuplicatePackets() {
    var buffer = AudioJitterBuffer<Int>(targetDelayFrames: 1)
    buffer.push(frameNumber: 4, packet: 1)
    buffer.push(frameNumber: 4, packet: 2)
    #expect(buffer.read() == .packet(frameNumber: 4, 2))
    buffer.push(frameNumber: 4, packet: 3)
    #expect(buffer.read() == .waiting)
}

@Test func jitterBufferWarmupHandlesHostileFrameNumberSpan() {
    // Frame numbers come from untrusted wire varints. A span exceeding Int.max
    // must not trap the mix-clock thread during warm-up.
    var buffer = AudioJitterBuffer<String>(targetDelayFrames: 3)
    buffer.push(frameNumber: 0, packet: "first")
    buffer.push(frameNumber: UInt64.max, packet: "far")
    // Warm-up completes on the huge span; the first frame is served and no trap
    // occurs computing last - first.
    #expect(buffer.read() == .packet(frameNumber: 0, "first"))
}
