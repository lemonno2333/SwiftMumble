import CryptoKit
import Foundation
import Security
import X509

public struct ClientIdentityInfo: Equatable, Sendable {
    public let subject: String
    public let fingerprintSHA256: String
    public let notBefore: Date?
    public let notAfter: Date?

    public init(subject: String, fingerprintSHA256: String, notBefore: Date?, notAfter: Date?) {
        self.subject = subject
        self.fingerprintSHA256 = fingerprintSHA256
        self.notBefore = notBefore
        self.notAfter = notAfter
    }
}

public struct ClientIdentityHandle: @unchecked Sendable {
    public let identity: SecIdentity
    public let info: ClientIdentityInfo

    public init(identity: SecIdentity, info: ClientIdentityInfo) {
        self.identity = identity
        self.info = info
    }
}

public enum ClientIdentityStoreError: LocalizedError {
    case keyGenerationFailed(String)
    case publicKeyUnavailable
    case publicKeyExportFailed(String)
    case certificateSigningFailed(String)
    case invalidCertificate
    case identityNotFound
    case exportFailed(OSStatus)
    case importFailed(OSStatus)
    case privateKeyUnavailable(OSStatus)
    case privateKeyPersistenceFailed(OSStatus)
    case keychainStatus(OSStatus)
    case identityUnavailable(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let message):
            "Key generation failed: \(message)"
        case .publicKeyUnavailable:
            "The public key is unavailable."
        case .publicKeyExportFailed(let message):
            "Public key export failed: \(message)"
        case .certificateSigningFailed(let message):
            "Certificate signing failed: \(message)"
        case .invalidCertificate:
            "Security.framework rejected the generated X.509 certificate."
        case .identityNotFound:
            "The PKCS#12 file does not contain a client identity."
        case .exportFailed(let status):
            "PKCS#12 export failed (\(status)): \(securityMessage(status))"
        case .importFailed(let status):
            "PKCS#12 import failed (\(status)): \(securityMessage(status))"
        case .privateKeyUnavailable(let status):
            "The imported private key is unavailable (\(status)): \(securityMessage(status))"
        case .privateKeyPersistenceFailed(let status):
            "The imported private key could not be saved (\(status)): \(securityMessage(status))"
        case .keychainStatus(let status):
            "Keychain operation failed (\(status)): \(securityMessage(status))"
        case .identityUnavailable(let status):
            "The certificate and private key could not be combined into an identity (\(status)): \(securityMessage(status))"
        }
    }

    private func securityMessage(_ status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
    }
}

public enum ClientIdentityStore {
    private static let privateKeyTag = Data("com.leo.SwiftMumble.client-identity.private-key".utf8)
    private static let certificateLabel = "SwiftMumble Client Identity"
    private static let certificateDataKey = "SwiftMumble.clientIdentity.certificateData"
    private static let notBeforeKey = "SwiftMumble.clientIdentity.notBefore"
    private static let notAfterKey = "SwiftMumble.clientIdentity.notAfter"
    private static let identityVersionKey = "SwiftMumble.clientIdentity.version"
    private static let currentIdentityVersion = 7

    public static func loadOrCreate() throws -> ClientIdentityHandle {
        if let existing = try load() { return existing }
        try deleteLegacyPrivateKeys()
        return try generate()
    }

    public static func load() throws -> ClientIdentityHandle? {
        guard UserDefaults.standard.integer(forKey: identityVersionKey) == currentIdentityVersion else {
            return nil
        }
        guard let certificateData = UserDefaults.standard.data(forKey: certificateDataKey) else {
            return nil
        }
        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            clearMetadata()
            throw ClientIdentityStoreError.invalidCertificate
        }
        let defaults = UserDefaults.standard
        let notBefore = defaults.object(forKey: notBeforeKey) as? Date
        let notAfter = defaults.object(forKey: notAfterKey) as? Date
        return try handle(for: certificate, notBefore: notBefore, notAfter: notAfter)
    }

    public static func regenerate() throws -> ClientIdentityHandle {
        try delete()
        return try generate()
    }

    public static func exportPKCS12(passphrase: String) throws -> Data {
        let handle = try loadOrCreate()
        return try exportPKCS12(identity: handle.identity, passphrase: passphrase)
    }

    static func exportPKCS12(identity: SecIdentity, passphrase: String) throws -> Data {
        var parameters = SecItemImportExportKeyParameters()
        parameters.passphrase = Unmanaged.passUnretained(passphrase as CFString)
        var exportedData: CFData?
        let status = SecItemExport(
            identity,
            .formatPKCS12,
            [],
            &parameters,
            &exportedData
        )
        guard status == errSecSuccess, let exportedData else {
            throw ClientIdentityStoreError.exportFailed(status)
        }
        return exportedData as Data
    }

    public static func importPKCS12(_ data: Data, passphrase: String) throws -> ClientIdentityHandle {
        let importResult = try importedIdentityResult(from: data, passphrase: passphrase)
        let imported = importResult.identity
        var certificate: SecCertificate?
        let certificateStatus = SecIdentityCopyCertificate(imported, &certificate)
        guard certificateStatus == errSecSuccess, let certificate else {
            throw ClientIdentityStoreError.invalidCertificate
        }
        let certificateData = SecCertificateCopyData(certificate) as Data

        if let currentData = UserDefaults.standard.data(forKey: certificateDataKey),
           currentData == certificateData,
           let current = try load() {
            return current
        }

        var importedPrivateKey: SecKey?
        let privateKeyStatus = SecIdentityCopyPrivateKey(imported, &importedPrivateKey)
        guard privateKeyStatus == errSecSuccess, let importedPrivateKey else {
            throw ClientIdentityStoreError.privateKeyUnavailable(privateKeyStatus)
        }
        var exportError: Unmanaged<CFError>?
        guard let privateKeyData = SecKeyCopyExternalRepresentation(
            importedPrivateKey,
            &exportError
        ) as Data? else {
            throw ClientIdentityStoreError.publicKeyExportFailed(
                exportError?.takeRetainedValue().localizedDescription ?? "The private key is not extractable."
            )
        }
        guard let attributes = SecKeyCopyAttributes(importedPrivateKey) as? [CFString: Any],
              let keyType = attributes[kSecAttrKeyType] else {
            throw ClientIdentityStoreError.publicKeyUnavailable
        }
        var creationError: Unmanaged<CFError>?
        let creationAttributes: [CFString: Any] = [
            kSecAttrKeyType: keyType,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        guard let persistentKey = SecKeyCreateWithData(
            privateKeyData as CFData,
            creationAttributes as CFDictionary,
            &creationError
        ) else {
            throw ClientIdentityStoreError.keyGenerationFailed(
                creationError?.takeRetainedValue().localizedDescription ?? "Could not recreate the imported private key."
            )
        }

        var oldPrivateKey: SecKey?
        if let current = try? load() {
            _ = SecIdentityCopyPrivateKey(current.identity, &oldPrivateKey)
        }

        if importResult.isPersistent {
            let updateQuery: [CFString: Any] = [
                kSecClass: kSecClassKey,
                kSecValueRef: importedPrivateKey
            ]
            let updateAttributes: [CFString: Any] = [
                kSecAttrApplicationTag: privateKeyTag,
                kSecAttrLabel: certificateLabel
            ]
            let updateStatus = SecItemUpdate(
                updateQuery as CFDictionary,
                updateAttributes as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw ClientIdentityStoreError.privateKeyPersistenceFailed(updateStatus)
            }
            let dates = certificateDates(certificate)
            let newHandle = try handle(
                for: certificate,
                notBefore: dates.notBefore,
                notAfter: dates.notAfter
            )
            if let oldCertificateData = UserDefaults.standard.data(forKey: certificateDataKey),
               let oldCertificate = SecCertificateCreateWithData(nil, oldCertificateData as CFData) {
                try? deleteCertificate(oldCertificate)
            }
            if let oldPrivateKey {
                SecItemDelete([kSecClass: kSecClassKey, kSecValueRef: oldPrivateKey] as CFDictionary)
            }
            saveMetadata(
                certificateData: certificateData,
                notBefore: dates.notBefore,
                notAfter: dates.notAfter
            )
            return newHandle
        }

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecValueRef: persistentKey,
            kSecAttrApplicationTag: privateKeyTag,
            kSecAttrLabel: certificateLabel,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrIsExtractable: true
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ClientIdentityStoreError.privateKeyPersistenceFailed(addStatus)
        }

        let dates = certificateDates(certificate)
        do {
            try addCertificate(certificate)
        } catch {
            SecItemDelete([kSecClass: kSecClassKey, kSecValueRef: persistentKey] as CFDictionary)
            throw error
        }
        let newHandle: ClientIdentityHandle
        do {
            newHandle = try handle(
                for: certificate,
                notBefore: dates.notBefore,
                notAfter: dates.notAfter
            )
        } catch {
            SecItemDelete([kSecClass: kSecClassKey, kSecValueRef: persistentKey] as CFDictionary)
            try? deleteCertificate(certificate)
            throw error
        }

        if let oldCertificateData = UserDefaults.standard.data(forKey: certificateDataKey),
           let oldCertificate = SecCertificateCreateWithData(nil, oldCertificateData as CFData) {
            try? deleteCertificate(oldCertificate)
        }
        if let oldPrivateKey {
            SecItemDelete([kSecClass: kSecClassKey, kSecValueRef: oldPrivateKey] as CFDictionary)
        }
        saveMetadata(
            certificateData: certificateData,
            notBefore: dates.notBefore,
            notAfter: dates.notAfter
        )
        return newHandle
    }

    public static func delete() throws {
        if let certificateData = UserDefaults.standard.data(forKey: certificateDataKey),
           let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) {
            try deleteCertificate(certificate)
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: privateKeyTag
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ClientIdentityStoreError.keychainStatus(status)
        }
        clearMetadata()
    }

    private static func generate() throws -> ClientIdentityHandle {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: privateKeyTag,
                kSecAttrLabel: certificateLabel,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecAttrIsExtractable: true
            ]
        ]
        var keyError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &keyError) else {
            throw ClientIdentityStoreError.keyGenerationFailed(
                keyError?.takeRetainedValue().localizedDescription ?? "Unknown Security.framework error"
            )
        }
        let notBefore = Date().addingTimeInterval(-300)
        let notAfter = Calendar(identifier: .gregorian).date(byAdding: .year, value: 10, to: notBefore)
            ?? notBefore.addingTimeInterval(10 * 365 * 24 * 60 * 60)
        let certificate: SecCertificate
        do {
            certificate = try SelfSignedCertificateBuilder.certificate(
                commonName: "SwiftMumble Client",
                privateKey: privateKey,
                notBefore: notBefore,
                notAfter: notAfter
            )
        } catch {
            try? delete()
            throw ClientIdentityStoreError.certificateSigningFailed(
                error.localizedDescription
            )
        }
        let certificateData = SecCertificateCopyData(certificate) as Data

        do {
            try addCertificate(certificate)
        } catch {
            try? delete()
            throw error
        }

        saveMetadata(certificateData: certificateData, notBefore: notBefore, notAfter: notAfter)
        do {
            return try handle(for: certificate, notBefore: notBefore, notAfter: notAfter)
        } catch {
            try? delete()
            throw error
        }
    }


    private static func handle(
        for certificate: SecCertificate,
        notBefore: Date?,
        notAfter: Date?
    ) throws -> ClientIdentityHandle {
        var identity: SecIdentity?
        let status = SecIdentityCreateWithCertificate(nil, certificate, &identity)
        guard status == errSecSuccess, let identity else {
            throw ClientIdentityStoreError.identityUnavailable(status)
        }
        let certificateData = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: certificateData)
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        let subject = SecCertificateCopySubjectSummary(certificate) as String? ?? certificateLabel
        return ClientIdentityHandle(
            identity: identity,
            info: ClientIdentityInfo(
                subject: subject,
                fingerprintSHA256: fingerprint,
                notBefore: notBefore,
                notAfter: notAfter
            )
        )
    }

    private static func clearMetadata() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: certificateDataKey)
        defaults.removeObject(forKey: notBeforeKey)
        defaults.removeObject(forKey: notAfterKey)
        defaults.removeObject(forKey: identityVersionKey)
    }

    private static func saveMetadata(certificateData: Data, notBefore: Date?, notAfter: Date?) {
        let defaults = UserDefaults.standard
        defaults.set(certificateData, forKey: certificateDataKey)
        defaults.set(notBefore, forKey: notBeforeKey)
        defaults.set(notAfter, forKey: notAfterKey)
        defaults.set(currentIdentityVersion, forKey: identityVersionKey)
    }

    static func importedIdentity(from data: Data, passphrase: String) throws -> SecIdentity {
        try importedIdentityResult(from: data, passphrase: passphrase).identity
    }

    private struct ImportedIdentityResult {
        let identity: SecIdentity
        let isPersistent: Bool
    }

    private static func importedIdentityResult(
        from data: Data,
        passphrase: String
    ) throws -> ImportedIdentityResult {
        var options: [CFString: Any] = [
            kSecImportExportPassphrase: passphrase
        ]
        let importsToMemory: Bool
        if #available(macOS 15.0, *) {
            options[kSecImportToMemoryOnly] = true
            importsToMemory = true
        } else {
            importsToMemory = false
        }
        var importedItems: CFArray?
        let status = SecPKCS12Import(
            data as CFData,
            options as CFDictionary,
            &importedItems
        )
        guard status == errSecSuccess else {
            throw ClientIdentityStoreError.importFailed(status)
        }
        guard let items = importedItems as? [[CFString: Any]],
              let identity = items.compactMap({ item -> SecIdentity? in
                  guard let value = item[kSecImportItemIdentity],
                        CFGetTypeID(value as CFTypeRef) == SecIdentityGetTypeID() else {
                      return nil
                  }
                  return (value as! SecIdentity)
              }).first else {
            throw ClientIdentityStoreError.identityNotFound
        }
        return ImportedIdentityResult(identity: identity, isPersistent: !importsToMemory)
    }

    private static func certificateDates(_ certificate: SecCertificate) -> (notBefore: Date?, notAfter: Date?) {
        let requestedKeys = [kSecOIDX509V1ValidityNotBefore, kSecOIDX509V1ValidityNotAfter] as CFArray
        guard let values = SecCertificateCopyValues(certificate, requestedKeys, nil) as NSDictionary? else {
            return (nil, nil)
        }
        func date(_ key: CFString) -> Date? {
            guard let property = values[key] as? NSDictionary else { return nil }
            return property[kSecPropertyKeyValue] as? Date
        }
        return (date(kSecOIDX509V1ValidityNotBefore), date(kSecOIDX509V1ValidityNotAfter))
    }

    private static func addCertificate(_ certificate: SecCertificate) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: certificate,
            kSecAttrLabel: certificateLabel
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw ClientIdentityStoreError.keychainStatus(status)
        }
    }

    private static func deleteCertificate(_ certificate: SecCertificate) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: certificate
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ClientIdentityStoreError.keychainStatus(status)
        }
    }

    private static func deleteLegacyPrivateKeys() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: privateKeyTag
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ClientIdentityStoreError.keychainStatus(status)
        }
    }
}

enum SelfSignedCertificateBuilder {
    static func certificate(
        commonName: String,
        privateKey: SecKey,
        notBefore: Date,
        notAfter: Date
    ) throws -> SecCertificate {
        let signingKey = try Certificate.PrivateKey(privateKey)
        let name = try DistinguishedName {
            CommonName(commonName)
        }
        let certificate = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: signingKey.publicKey,
            notValidBefore: notBefore,
            notValidAfter: notAfter,
            issuer: name,
            subject: name,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true, keyEncipherment: true))
                try ExtendedKeyUsage([.clientAuth])
            },
            issuerPrivateKey: signingKey
        )
        return try SecCertificate.makeWithCertificate(certificate)
    }
}
