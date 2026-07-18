import Foundation
import Network

struct DiscoveredMumbleServer: Identifiable, Hashable, Sendable {
    var id: String { "\(name)|\(host)|\(port)" }
    var name: String
    var host: String
    var port: UInt16
}

struct LANDiscoveryRegistry<Endpoint: Hashable> {
    private var serversByEndpoint: [Endpoint: DiscoveredMumbleServer] = [:]

    var knownEndpoints: Set<Endpoint> { Set(serversByEndpoint.keys) }
    var sortedServers: [DiscoveredMumbleServer] {
        Set(serversByEndpoint.values).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @discardableResult
    mutating func store(_ server: DiscoveredMumbleServer, for endpoint: Endpoint) -> Bool {
        let previousServers = Set(serversByEndpoint.values)
        serversByEndpoint[endpoint] = server
        return previousServers != Set(serversByEndpoint.values)
    }

    @discardableResult
    mutating func remove(endpoint: Endpoint) -> Bool {
        let previousServers = Set(serversByEndpoint.values)
        guard serversByEndpoint.removeValue(forKey: endpoint) != nil else { return false }
        return previousServers != Set(serversByEndpoint.values)
    }

    mutating func removeAll() {
        serversByEndpoint.removeAll()
    }
}

final class LANMumbleDiscovery: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.leo.SwiftMumble.discovery")
    private var browser: NWBrowser?
    private var resolving: [NWEndpoint: NWConnection] = [:]
    private let update: @Sendable ([DiscoveredMumbleServer]) -> Void
    private var registry = LANDiscoveryRegistry<NWEndpoint>()

    init(update: @escaping @Sendable ([DiscoveredMumbleServer]) -> Void) {
        self.update = update
    }

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_mumble._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.resolve(results.map(\.endpoint))
        }
        browser.stateUpdateHandler = { state in
            if case .failed = state { browser.cancel() }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolving.values.forEach { $0.cancel() }
        resolving.removeAll()
        registry.removeAll()
        update([])
    }

    private func resolve(_ endpoints: [NWEndpoint]) {
        let live = Set(endpoints)
        var removedServer = false
        let knownEndpoints = Set(resolving.keys).union(registry.knownEndpoints)
        for endpoint in knownEndpoints where !live.contains(endpoint) {
            resolving.removeValue(forKey: endpoint)?.cancel()
            removedServer = registry.remove(endpoint: endpoint) || removedServer
        }
        if removedServer { publish() }
        for endpoint in endpoints where resolving[endpoint] == nil {
            let connection = NWConnection(to: endpoint, using: .tcp)
            resolving[endpoint] = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, let connection else { return }
                switch state {
                case .ready:
                    if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                        let name: String
                        if case .service(let serviceName, _, _, _) = endpoint { name = serviceName }
                        else { name = String(describing: host) }
                        let server = DiscoveredMumbleServer(
                            name: name,
                            host: String(describing: host),
                            port: port.rawValue
                        )
                        if self.registry.store(server, for: endpoint) { self.publish() }
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    self.resolving.removeValue(forKey: endpoint)
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func publish() {
        update(registry.sortedServers)
    }
}
