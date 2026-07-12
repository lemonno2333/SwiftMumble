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
}
