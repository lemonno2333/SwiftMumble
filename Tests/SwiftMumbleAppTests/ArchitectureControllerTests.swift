import Foundation
import MumbleProtocol
import Testing
@testable import SwiftMumbleApp

@MainActor
@Test func serverRepositoryOwnsPersistenceAndSessionSelection() {
    let first = MumbleServer(name: "First", host: "first.example")
    let second = MumbleServer(name: "Second", host: "second.example")
    var savedSnapshots: [[MumbleServer]] = []
    let repository = ServerRepository(servers: [first]) { savedSnapshots.append($0) }

    repository.add(second)
    #expect(repository.servers.count == 2)
    #expect(savedSnapshots.last?.map(\.id) == [first.id, second.id])

    let selected = repository.select(second.id)
    #expect(selected)
    let changedAtSessionStart = repository.beginSession(serverID: second.id)
    #expect(!changedAtSessionStart)
    #expect(repository.activeServer?.id == second.id)

    repository.endSession()
    #expect(repository.activeID == nil)
}

@MainActor
@Test func serverRepositoryUpdatesCertificateThroughOnePersistenceBoundary() {
    let server = MumbleServer(name: "Server", host: "voice.example")
    var saveCount = 0
    let repository = ServerRepository(servers: [server]) { _ in saveCount += 1 }

    let updated = repository.updateCertificateFingerprint("aabb", serverID: server.id)

    #expect(updated?.certificateFingerprint == "aabb")
    #expect(repository.servers.first?.certificateFingerprint == "aabb")
    #expect(saveCount == 1)
}

@MainActor
@Test func connectionCoordinatorResetsNewConnectionAndSynchronizationState() {
    let defaults = controllerDefaults()
    let coordinator = ConnectionCoordinator(defaults: defaults)
    let serverID = UUID()
    coordinator.isReconnecting = true
    coordinator.reconnectAttempt = 3
    coordinator.suppressReconnect = true
    coordinator.didSynchronize = true

    coordinator.beginConnection(serverID: serverID, isReconnect: false)
    #expect(coordinator.reconnectServerID == serverID)
    #expect(!coordinator.isReconnecting)
    #expect(coordinator.reconnectAttempt == 0)
    #expect(!coordinator.suppressReconnect)
    #expect(!coordinator.didSynchronize)

    coordinator.isReconnecting = true
    let wasReconnecting = coordinator.markSynchronized()
    #expect(wasReconnecting)
    #expect(coordinator.didSynchronize)
    #expect(!coordinator.isReconnecting)
}

@MainActor
@Test func connectionCoordinatorDisablingReconnectClearsPendingState() {
    let defaults = controllerDefaults()
    let coordinator = ConnectionCoordinator(defaults: defaults)
    coordinator.isReconnecting = true
    coordinator.reconnectAttempt = 4

    coordinator.setAutoReconnectEnabled(false)

    #expect(!coordinator.autoReconnectEnabled)
    #expect(!coordinator.isReconnecting)
    #expect(coordinator.reconnectAttempt == 0)
    #expect(defaults.object(forKey: "autoReconnectEnabled") as? Bool == false)
}

@MainActor
@Test func shortcutControllerOwnsOverridesTargetsAndClamping() {
    let defaults = controllerDefaults()
    let controller = ShortcutController(defaults: defaults)
    let serverID = UUID()

    controller.setOverrideEnabled(true, for: serverID)
    controller.setVoiceTarget(.user(session: 42, name: "User"))
    controller.setIdleTimeoutMinutes(999)

    #expect(controller.usesOverride(for: serverID))
    #expect(controller.serverOverrides[serverID.uuidString] != nil)
    #expect(controller.voiceTarget == .user(session: 42, name: "User"))
    #expect(controller.idleTimeoutMinutes == 240)
}

@MainActor
@Test func audioSessionControllerBacksSessionFacadeState() {
    let session = SessionStore(servers: [], performStartup: false)

    session.masterOutputVolume = 1.5
    session.transmissionMode = .continuous
    session.audioPacketsReceived = 12

    #expect(session.audioSession.masterOutputVolume == 1.5)
    #expect(session.audioSession.transmissionMode == .continuous)
    #expect(session.audioSession.packetsReceived == 12)
}

private func controllerDefaults() -> UserDefaults {
    let suiteName = "ArchitectureControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
