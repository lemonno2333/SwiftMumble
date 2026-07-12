import Foundation
import Testing
@testable import MumbleAudio

@Test func transmitPipelineNumbersEncodedFrames() throws {
    let pipeline = try AudioTransmitPipeline()
    let silence = [Float](repeating: 0, count: 480)

    let first = try pipeline.encode(samples: silence)
    let second = try pipeline.encode(samples: silence)

    #expect(first.frameNumber == 0)
    #expect(second.frameNumber == 1)
    #expect(!first.opusData.isEmpty)
    #expect(pipeline.takeTerminatorFrameNumber() == 2)
}

@Test func transmitPipelineAggregatesConfiguredTenMillisecondFrames() throws {
    let pipeline = try AudioTransmitPipeline(framesPerPacket: 2)
    let silence = [Float](repeating: 0, count: 480)
    #expect(try pipeline.enqueue10msFrame(samples: silence) == nil)
    let firstValue = try pipeline.enqueue10msFrame(samples: silence)
    let first = try #require(firstValue)
    #expect(first.frameNumber == 0)
    #expect(try pipeline.enqueue10msFrame(samples: silence) == nil)
    let secondValue = try pipeline.enqueue10msFrame(samples: silence)
    let second = try #require(secondValue)
    #expect(second.frameNumber == 2)
    #expect(pipeline.takeTerminatorFrameNumber() == 4)
}
