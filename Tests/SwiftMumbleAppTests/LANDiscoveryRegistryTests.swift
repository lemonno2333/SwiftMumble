import Testing
@testable import SwiftMumbleApp

@Test func lanDiscoveryRegistryAddsUpdatesAndRemovesEndpoints() {
    var registry = LANDiscoveryRegistry<String>()
    let first = DiscoveredMumbleServer(name: "Zulu", host: "10.0.0.1", port: 64738)
    let second = DiscoveredMumbleServer(name: "Alpha", host: "10.0.0.2", port: 64738)

    let storedFirst = registry.store(first, for: "endpoint-1")
    let storedSecond = registry.store(second, for: "endpoint-2")
    #expect(storedFirst)
    #expect(storedSecond)
    #expect(registry.sortedServers.map(\.name) == ["Alpha", "Zulu"])
    #expect(registry.knownEndpoints == Set(["endpoint-1", "endpoint-2"]))

    let updated = DiscoveredMumbleServer(name: "Beta", host: "10.0.0.3", port: 64738)
    let storedUpdate = registry.store(updated, for: "endpoint-1")
    #expect(storedUpdate)
    #expect(registry.sortedServers.map(\.name) == ["Alpha", "Beta"])

    let removedSecond = registry.remove(endpoint: "endpoint-2")
    #expect(removedSecond)
    #expect(registry.sortedServers == [updated])
    let removedMissing = registry.remove(endpoint: "missing")
    #expect(!removedMissing)
}

@Test func lanDiscoveryRegistryKeepsServerWhileAnotherEndpointStillPublishesIt() {
    var registry = LANDiscoveryRegistry<String>()
    let server = DiscoveredMumbleServer(name: "Mumble", host: "10.0.0.1", port: 64738)

    let storedFirst = registry.store(server, for: "wifi")
    let storedDuplicate = registry.store(server, for: "ethernet")
    #expect(storedFirst)
    #expect(!storedDuplicate)
    #expect(registry.sortedServers == [server])

    let removedFirst = registry.remove(endpoint: "wifi")
    #expect(!removedFirst)
    #expect(registry.sortedServers == [server])

    let removedLast = registry.remove(endpoint: "ethernet")
    #expect(removedLast)
    #expect(registry.sortedServers.isEmpty)
}
