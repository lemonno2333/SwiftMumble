import Foundation
import Testing
@testable import MumbleProtocol

@Test func frameRoundTripAcrossPartialReads() throws {
    let expected = MumbleFrame(type: .authenticate, payload: Data([0x08, 0x01, 0x10, 0x01]))
    let bytes = expected.encoded()
    var decoder = MumbleFrameDecoder()

    #expect(try decoder.append(bytes.prefix(3)).isEmpty)
    #expect(try decoder.append(bytes.dropFirst(3).prefix(4)).isEmpty)
    #expect(try decoder.append(bytes.dropFirst(7)) == [expected])
}

@Test func decoderReturnsMultipleFrames() throws {
    let first = MumbleFrame(type: .ping, payload: Data([1, 2]))
    let second = MumbleFrame(type: .serverSync, payload: Data([3, 4, 5]))
    var stream = first.encoded()
    stream.append(second.encoded())
    var decoder = MumbleFrameDecoder()

    #expect(try decoder.append(stream) == [first, second])
}

@Test func decoderRejectsOversizedPayload() {
    var bytes = Data([0, 3, 0, 0, 0, 9])
    bytes.append(Data(repeating: 0, count: 9))
    var decoder = MumbleFrameDecoder(maximumPayloadLength: 8)

    #expect(throws: MumbleFrameError.payloadTooLarge(9)) {
        try decoder.append(bytes)
    }
}
