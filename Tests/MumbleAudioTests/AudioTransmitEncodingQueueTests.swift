import Foundation
import Testing
@testable import MumbleAudio

@MainActor
@Test func transmitEncodingQueuePreservesFramesBeforeTerminator() async throws {
    let queue = AudioTransmitEncodingQueue()
    let samples = [Float](repeating: 0.1, count: 480)
    let configuration = OpusEncoderConfiguration()

    let first = await encode(
        queue,
        samples: samples,
        configuration: configuration,
        framesPerPacket: 2
    )
    guard case .buffered = first else {
        Issue.record("The first 10ms frame should remain buffered")
        return
    }

    let second = await encode(
        queue,
        samples: samples,
        configuration: configuration,
        framesPerPacket: 2
    )
    guard case .frame(let encoded) = second else {
        Issue.record("The second 10ms frame should produce one Opus packet")
        return
    }
    #expect(encoded.frameNumber == 0)

    let terminator = await withCheckedContinuation { continuation in
        queue.finish { continuation.resume(returning: $0) }
    }
    #expect(terminator == 2)
}

@MainActor
private func encode(
    _ queue: AudioTransmitEncodingQueue,
    samples: [Float],
    configuration: OpusEncoderConfiguration,
    framesPerPacket: Int
) async -> AudioTransmitEncodingResult {
    await withCheckedContinuation { continuation in
        queue.enqueue(
            samples: samples,
            configuration: configuration,
            framesPerPacket: framesPerPacket
        ) { continuation.resume(returning: $0) }
    }
}
