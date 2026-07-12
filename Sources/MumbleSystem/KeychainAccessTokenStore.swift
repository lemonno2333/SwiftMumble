import Foundation
import Security

public enum KeychainAccessTokenStore {
    private static let service = "com.leo.SwiftMumble.server-access-tokens"

    public static func save(_ tokens: [String], account: String) throws {
        let normalized = normalize(tokens)
        if normalized.isEmpty {
            try delete(account: account)
            return
        }
        let data = try JSONEncoder().encode(normalized)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainPasswordError.unexpectedStatus(updateStatus)
        }
        var item = query
        for (key, value) in attributes { item[key] = value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainPasswordError.unexpectedStatus(addStatus)
        }
    }

    public static func load(account: String) throws -> [String] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw KeychainPasswordError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let tokens = try? JSONDecoder().decode([String].self, from: data) else {
            throw KeychainPasswordError.invalidData
        }
        return normalize(tokens)
    }

    public static func delete(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainPasswordError.unexpectedStatus(status)
        }
    }

    private static func normalize(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        return tokens.compactMap { token in
            let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
    }
}
