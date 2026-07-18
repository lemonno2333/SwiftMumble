import Foundation

public enum KeychainAccessTokenStore {
    private static let service = "com.leo.SwiftMumble.server-access-tokens"

    public static func save(_ tokens: [String], account: String) throws {
        let normalized = normalize(tokens)
        if normalized.isEmpty {
            try delete(account: account)
            return
        }
        let data = try JSONEncoder().encode(normalized)
        try KeychainGenericPasswordStore.save(data, service: service, account: account)
    }

    public static func load(account: String) throws -> [String] {
        guard let data = try KeychainGenericPasswordStore.load(service: service, account: account) else { return [] }
        guard let tokens = try? JSONDecoder().decode([String].self, from: data) else {
            throw KeychainPasswordError.invalidData
        }
        return normalize(tokens)
    }

    public static func delete(account: String) throws {
        try KeychainGenericPasswordStore.delete(service: service, account: account)
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
