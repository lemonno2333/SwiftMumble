import Foundation
import MumbleProtocol

enum SavedServerStore {
    private static let key = "savedMumbleServers"

    static func load() -> [MumbleServer] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let servers = try? JSONDecoder().decode([MumbleServer].self, from: data) else {
            return []
        }
        return servers
    }

    static func save(_ servers: [MumbleServer]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
