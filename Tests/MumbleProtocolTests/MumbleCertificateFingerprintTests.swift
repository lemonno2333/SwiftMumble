import Foundation
import Testing
@testable import MumbleProtocol

@Test func certificateFingerprintParsesCommonFormatting() throws {
    let der = Data("certificate".utf8)
    let fingerprint = MumbleCertificateFingerprint(certificateDER: der)
    let parsed = try #require(MumbleCertificateFingerprint(hex: fingerprint.formatted.uppercased()))

    #expect(parsed == fingerprint)
    #expect(fingerprint.bytes.count == 32)
    #expect(fingerprint.hex.count == 64)
}

@Test func certificateFingerprintRejectsWrongLength() {
    #expect(MumbleCertificateFingerprint(hex: "aa:bb:cc") == nil)
    #expect(MumbleCertificateFingerprint(bytes: Data(repeating: 0, count: 31)) == nil)
    #expect(MumbleCertificateFingerprint(bytes: Data(repeating: 0, count: 33)) == nil)
}

@Test func certificateFingerprintAcceptsRawSHA256Bytes() throws {
    let bytes = Data((0..<32).map(UInt8.init))
    let fingerprint = try #require(MumbleCertificateFingerprint(bytes: bytes))
    #expect(fingerprint.bytes == bytes)
}

@Test func certificatePinEvaluatorDistinguishesPinStates() throws {
    let actual = try #require(MumbleCertificateFingerprint(bytes: Data(repeating: 1, count: 32)))
    let other = Data(repeating: 2, count: 32)

    #expect(MumbleCertificatePinEvaluator.evaluate(actual: actual, pinnedSHA256: nil) == .notPinned)
    #expect(MumbleCertificatePinEvaluator.evaluate(actual: actual, pinnedSHA256: actual.bytes) == .match)
    #expect(
        MumbleCertificatePinEvaluator.evaluate(actual: actual, pinnedSHA256: other)
            == .mismatch(
                expected: try #require(MumbleCertificateFingerprint(bytes: other)),
                actual: actual
            )
    )
    #expect(
        MumbleCertificatePinEvaluator.evaluate(actual: actual, pinnedSHA256: Data([0]))
            == .invalidPinnedFingerprint
    )
}
