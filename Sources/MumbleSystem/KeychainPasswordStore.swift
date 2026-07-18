import Foundation
import Security

public enum KeychainPasswordError: Error {
    case unexpectedStatus(OSStatus)
    case invalidData
}

public enum KeychainPasswordStore {
    private static let service = "com.leo.SwiftMumble.server-password"

    public static func save(_ password: String, account: String) throws {
        try KeychainGenericPasswordStore.save(Data(password.utf8), service: service, account: account)
    }

    public static func load(account: String) throws -> String? {
        guard let data = try KeychainGenericPasswordStore.load(service: service, account: account) else { return nil }
        guard let password = String(data: data, encoding: .utf8) else {
            throw KeychainPasswordError.invalidData
        }
        return password
    }

    public static func delete(account: String) throws {
        try KeychainGenericPasswordStore.delete(service: service, account: account)
    }
}
