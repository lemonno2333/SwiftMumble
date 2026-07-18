import MumbleProtocol
import Observation

@MainActor
@Observable
final class ServerRepository {
    private(set) var servers: [MumbleServer]
    private var selection: ServerSessionSelection<MumbleServer.ID>

    @ObservationIgnored private let save: ([MumbleServer]) -> Void

    var selectedID: MumbleServer.ID? { selection.selectedID }
    var activeID: MumbleServer.ID? { selection.activeID }
    var selectedServer: MumbleServer? { server(id: selectedID) }
    var activeServer: MumbleServer? { server(id: activeID) }

    init(
        servers: [MumbleServer],
        selectedID: MumbleServer.ID? = nil,
        activeID: MumbleServer.ID? = nil,
        save: @escaping ([MumbleServer]) -> Void = SavedServerStore.save
    ) {
        self.servers = servers
        self.save = save
        selection = ServerSessionSelection(
            selectedID: selectedID ?? activeID ?? servers.first?.id,
            activeID: activeID
        )
    }

    func server(id: MumbleServer.ID?) -> MumbleServer? {
        guard let id else { return nil }
        return servers.first { $0.id == id }
    }

    @discardableResult
    func select(_ id: MumbleServer.ID) -> Bool {
        selection.select(id)
    }

    @discardableResult
    func forceSelect(_ id: MumbleServer.ID?) -> Bool {
        selection.forceSelect(id)
    }

    @discardableResult
    func beginSession(serverID: MumbleServer.ID) -> Bool {
        selection.beginSession(serverID: serverID)
    }

    func endSession() {
        selection.endSession()
    }

    func add(_ server: MumbleServer) {
        servers.append(server)
        save(servers)
    }

    @discardableResult
    func update(_ server: MumbleServer) -> Bool {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return false }
        servers[index] = server
        save(servers)
        return true
    }

    @discardableResult
    func remove(id: MumbleServer.ID) -> Bool {
        let previousCount = servers.count
        servers.removeAll { $0.id == id }
        guard servers.count != previousCount else { return false }
        save(servers)
        return true
    }

    @discardableResult
    func updateCertificateFingerprint(_ fingerprint: String, serverID: MumbleServer.ID) -> MumbleServer? {
        guard let index = servers.firstIndex(where: { $0.id == serverID }) else { return nil }
        servers[index].certificateFingerprint = fingerprint
        save(servers)
        return servers[index]
    }
}
