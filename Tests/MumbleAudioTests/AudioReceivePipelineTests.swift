import Foundation
import Testing
@testable import MumbleAudio

@Test func receivePipelineReordersAndUsesPacketLossConcealment() throws {
    let encoder = try OpusEncoder()
    let pipeline = try AudioReceivePipeline(targetDelayFrames: 2)
    let silence = [Float](repeating: 0, count: 480)
    let packet = try encoder.encode(samples: silence)

    pipeline.push(
        frameNumber: 0,
        packet: BufferedAudioPacket(opusData: packet),
        arrivalTime: 10
    )
    pipeline.push(
        frameNumber: 2,
        packet: BufferedAudioPacket(opusData: packet),
        arrivalTime: 10.02
    )

    guard case .samples(let first) = try pipeline.read() else {
        Issue.record("Expected first decoded frame")
        return
    }
    guard case .samples(let concealed) = try pipeline.read() else {
        Issue.record("Expected packet-loss concealment frame")
        return
    }

    #expect(first.count == 480)
    #expect(concealed.count == 480)
    guard case .samples(let third) = try pipeline.read() else {
        Issue.record("Expected reordered third frame")
        return
    }
    #expect(third.count == 480)
}

@Test func receivePipelineSplitsMultiFrameOpusWithoutInventingLoss() throws {
    let encoder = try OpusEncoder()
    let pipeline = try AudioReceivePipeline(targetDelayFrames: 2)
    let twentyMilliseconds = [Float](repeating: 0.1, count: 960)
    let packet = try encoder.encode(samples: twentyMilliseconds)

    pipeline.push(frameNumber: 0, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10)
    pipeline.push(frameNumber: 2, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10.02)

    for _ in 0..<4 {
        guard case .samples(let samples) = try pipeline.read() else {
            Issue.record("Expected a decoded 10ms frame without PLC gaps")
            return
        }
        #expect(samples.count == 480)
    }
    #expect(try pipeline.read() == .waiting)
}

@Test func receivePipelineAcceptsAudioAfterLongWaitingPeriod() throws {
    let encoder = try OpusEncoder()
    let pipeline = try AudioReceivePipeline(targetDelayFrames: 2)
    let packet = try encoder.encode(samples: [Float](repeating: 0.1, count: 480))

    for _ in 0..<250 {
        #expect(try pipeline.read() == .waiting)
    }

    pipeline.push(frameNumber: 0, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10)
    pipeline.push(frameNumber: 1, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10.01)

    guard case .samples(let samples) = try pipeline.read() else {
        Issue.record("Expected audio after an extended waiting period")
        return
    }
    #expect(samples.count == 480)
}

@Test func receivePipelineAcceptsNewTalkSpurtAfterTerminator() throws {
    let encoder = try OpusEncoder()
    let pipeline = try AudioReceivePipeline(targetDelayFrames: 2)
    let packet = try encoder.encode(samples: [Float](repeating: 0.1, count: 480))
    let terminator = BufferedAudioPacket(opusData: Data(), isTerminator: true)

    pipeline.push(frameNumber: 0, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10)
    pipeline.push(frameNumber: 1, packet: terminator, arrivalTime: 10.01)
    guard case .samples = try pipeline.read() else {
        Issue.record("Expected the first talk spurt")
        return
    }
    #expect(try pipeline.read() == .finished)

    pipeline.push(frameNumber: 10, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10.1)
    pipeline.push(frameNumber: 11, packet: BufferedAudioPacket(opusData: packet), arrivalTime: 10.11)
    guard case .samples(let samples) = try pipeline.read() else {
        Issue.record("Expected audio from a new talk spurt on the same pipeline")
        return
    }
    #expect(samples.count == 480)
}
