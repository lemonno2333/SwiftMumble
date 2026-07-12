import Foundation
import Security
import Testing
@testable import MumbleSystem

@Test func selfSignedCertificateBuilderProducesValidX509() throws {
    let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeySizeInBits: 2048
    ]
    var error: Unmanaged<CFError>?
    let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
    let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
    let publicData = try #require(SecKeyCopyExternalRepresentation(publicKey, &error) as Data?)
    let now = Date()
    let tbs = SelfSignedCertificateBuilder.tbsCertificate(
        commonName: "SwiftMumble Test",
        rsaPublicKeyPKCS1: publicData,
        notBefore: now.addingTimeInterval(-60),
        notAfter: now.addingTimeInterval(3600)
    )
    let signature = try #require(
        SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbs as CFData,
            &error
        ) as Data?
    )
    let certificateData = SelfSignedCertificateBuilder.certificate(
        tbsCertificate: tbs,
        signature: signature
    )
    let certificate = try #require(SecCertificateCreateWithData(nil, certificateData as CFData))
    #expect(SecCertificateCopySubjectSummary(certificate) as String? == "SwiftMumble Test")
}

@Test func clientIdentityRoundTripsThroughPasswordProtectedPKCS12() throws {
    let keyTag = Data("SwiftMumbleTests.\(UUID().uuidString)".utf8)
    var storedCertificate: SecCertificate?
    defer {
        SecItemDelete([
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: keyTag
        ] as CFDictionary)
        if let storedCertificate {
            SecItemDelete([
                kSecClass: kSecClassCertificate,
                kSecValueRef: storedCertificate
            ] as CFDictionary)
        }
    }
    let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeySizeInBits: 2048,
        kSecPrivateKeyAttrs: [
            kSecAttrIsPermanent: true,
            kSecAttrApplicationTag: keyTag,
            kSecAttrIsExtractable: true
        ]
    ]
    var error: Unmanaged<CFError>?
    let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
    let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
    let publicData = try #require(SecKeyCopyExternalRepresentation(publicKey, &error) as Data?)
    let now = Date()
    let tbs = SelfSignedCertificateBuilder.tbsCertificate(
        commonName: "SwiftMumble PKCS12 Test",
        rsaPublicKeyPKCS1: publicData,
        notBefore: now.addingTimeInterval(-60),
        notAfter: now.addingTimeInterval(3600)
    )
    let signature = try #require(
        SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbs as CFData,
            &error
        ) as Data?
    )
    let certificateData = SelfSignedCertificateBuilder.certificate(
        tbsCertificate: tbs,
        signature: signature
    )
    let certificate = try #require(SecCertificateCreateWithData(nil, certificateData as CFData))
    storedCertificate = certificate
    #expect(SecItemAdd([
        kSecClass: kSecClassCertificate,
        kSecValueRef: certificate,
        kSecAttrLabel: "SwiftMumble PKCS12 Test \(UUID().uuidString)"
    ] as CFDictionary, nil) == errSecSuccess)
    var identity: SecIdentity?
    #expect(SecIdentityCreateWithCertificate(nil, certificate, &identity) == errSecSuccess)
    let resolvedIdentity = try #require(identity)

    let archive = try ClientIdentityStore.exportPKCS12(
        identity: resolvedIdentity,
        passphrase: "correct horse battery staple"
    )
    #expect(!archive.isEmpty)
    let imported = try ClientIdentityStore.importedIdentity(
        from: archive,
        passphrase: "correct horse battery staple"
    )
    var importedCertificate: SecCertificate?
    #expect(SecIdentityCopyCertificate(imported, &importedCertificate) == errSecSuccess)
    let resolvedCertificate = try #require(importedCertificate)
    #expect(SecCertificateCopyData(resolvedCertificate) as Data == certificateData)
}
