import Foundation
import Testing
@testable import MumbleAudio

private func pull(_ pipeline: AudioReceivePipeline) -> [Float]? {
    var output = [Float](repeating: 0, count: AudioReceivePipeline.frameLength)
    let produced = output.withUnsafeMutableBufferPointer { pipeline.pull(into: $0.baseAddress!) }
    return produced ? output : nil
}

@Test func receivePipelineDecodesInArrivalOrder() throws {
    let encoder = try OpusEncoder()
    let pipeline = try AudioReceivePipeline(targetDelayFrames: 2)
    let packet = try encoder.encode(samples: [Float](repeating: 0.1, count: 480))

    pipeline.push(frameNumber: 0, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10)
    pipeline.push(frameNumber: 1, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10.01)

    // Warmed up (2 frames buffered): the first pull yields decoded audio.
    let first = pull(pipeline)
    #expect(first?.count == 480)
    let second = pull(pipeline)
    #expect(second?.count == 480)
}

@Test func receivePipelineWaitsSilentlyBeforeWarmup() throws {
    let encoder = try OpusEncoder()
    let pipeline = try AudioReceivePipeline(targetDelayFrames: 3)
    let packet = try encoder.encode(samples: [Float](repeating: 0.1, count: 480))

    // Idle source produces nothing (returns false, not silence frames).
    #expect(pull(pipeline) == nil)

    // One packet is below the warm-up threshold; still idle.
    pipeline.push(frameNumber: 0, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10)
    #expect(pull(pipeline) == nil)
}

@Test func receivePipelineConcealsLateFrameWithoutAccumulatingDelay() throws {
    let encoder = try OpusEncoder()
    let pipeline = try AudioReceivePipeline(targetDelayFrames: 2)
    let packet = try encoder.encode(samples: [Float](repeating: 0.2, count: 480))

    // Frames 0 and 2 arrive; frame 1 is late (a gap the buffer can see past).
    pipeline.push(frameNumber: 0, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10)
    pipeline.push(frameNumber: 2, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10.02)

    #expect(pull(pipeline)?.count == 480) // frame 0, decoded
    #expect(pull(pipeline)?.count == 480) // frame 1, concealed (PLC)
    #expect(pull(pipeline)?.count == 480) // frame 2, decoded
    #expect(pipeline.concealedFrameCount == 1)

    // A very late frame 1 now arrives — its slot was already concealed, so it
    // must be dropped rather than queued behind newer audio. The next pull
    // conceals again (frame 3 is genuinely absent), proving frame 1 never
    // re-entered the stream as decoded audio.
    pipeline.push(frameNumber: 1, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10.05)
    #expect(pull(pipeline)?.count == 480)
    #expect(pipeline.concealedFrameCount == 2)
}

@Test func receivePipelineSplitsMultiFrameOpusWithoutInventingLoss() throws {
    let encoder = try OpusEncoder()
    let pipeline = try AudioReceivePipeline(targetDelayFrames: 2)
    let twentyMilliseconds = [Float](repeating: 0.1, count: 960)
    let packet = try encoder.encode(samples: twentyMilliseconds)

    pipeline.push(frameNumber: 0, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10)
    pipeline.push(frameNumber: 2, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10.02)

    // Two 20 ms packets = four 10 ms frames, no concealment while real
    // audio is flowing.
    for _ in 0..<4 {
        #expect(pull(pipeline)?.count == 480)
    }
    #expect(pipeline.concealedFrameCount == 0)
}

@Test func receivePipelineEndsSpurtOnTerminator() throws {
    let encoder = try OpusEncoder()
    let pipeline = try AudioReceivePipeline(targetDelayFrames: 2)
    let packet = try encoder.encode(samples: [Float](repeating: 0.1, count: 480))
    let terminator = BufferedAudioPacket(opusData: Data(), isTerminator: true)

    pipeline.push(frameNumber: 0, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10)
    pipeline.push(frameNumber: 1, packet: terminator, arrivalTime: 10.01)
    #expect(pull(pipeline)?.count == 480)  // frame 0
    #expect(pull(pipeline) == nil)          // terminator ends the spurt

    // A new spurt on the same pipeline warms up and plays again.
    pipeline.push(frameNumber: 10, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10.1)
    pipeline.push(frameNumber: 11, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10.11)
    #expect(pull(pipeline)?.count == 480)
}

@Test func receivePipelineEndsSpurtAfterSustainedConcealment() throws {
    let encoder = try OpusEncoder()
    let pipeline = try AudioReceivePipeline(targetDelayFrames: 2, maximumConsecutiveConcealedFrames: 3)
    let packet = try encoder.encode(samples: [Float](repeating: 0.2, count: 480))

    // Establish a spurt, then a far-future frame so every intervening slot is
    // concealed until the ceiling forces the spurt to end.
    pipeline.push(frameNumber: 0, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10)
    pipeline.push(frameNumber: 50, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10.02)

    #expect(pull(pipeline)?.count == 480) // frame 0 decoded, spurt active
    var concealed = 0
    while pull(pipeline) != nil { concealed += 1 }
    // Ends within the ceiling rather than concealing all 49 missing slots.
    #expect(concealed <= 3)
}
