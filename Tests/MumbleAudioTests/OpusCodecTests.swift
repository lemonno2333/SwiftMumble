import Foundation
import Testing
@testable import MumbleAudio

@Test func opusRoundTripProducesOneTenMillisecondFrame() throws {
    let encoder = try OpusEncoder()
    let decoder = try OpusDecoder()
    let samples = (0..<480).map { index in
        Float(sin(2 * Double.pi * 440 * Double(index) / 48_000)) * 0.25
    }

    let packet = try encoder.encode(samples: samples)
    let decoded = try decoder.decode(packet: packet)

    #expect(!packet.isEmpty)
    #expect(packet.count < samples.count * MemoryLayout<Float>.size)
    #expect(decoded.count == 480)
    #expect(decoded.allSatisfy { $0.isFinite })
}

@Test func opusEncoderConfigurationClampsUnsafeValues() throws {
    let configuration = OpusEncoderConfiguration(
        bitrate: 1,
        complexity: 99,
        expectedPacketLossPercent: 80,
        inbandFEC: true,
        lowLatency: true
    )
    let encoder = try OpusEncoder(configuration: configuration)

    #expect(encoder.configuration.bitrate == 12_000)
    #expect(encoder.configuration.complexity == 10)
    #expect(encoder.configuration.expectedPacketLossPercent == 30)
    #expect(encoder.configuration.lowLatency)
}
