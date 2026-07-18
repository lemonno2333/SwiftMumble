import Foundation
import MumbleProtocol
import Observation

@MainActor
@Observable
final class ConnectionCoordinator {
    var autoReconnectEnabled: Bool
    var isReconnecting = false
    var reconnectAttempt = 0

    @ObservationIgnored var connectionTask: Task<Void, Never>?
    @ObservationIgnored var teardownTask: Task<Void, Never>?
    @ObservationIgnored var pingTask: Task<Void, Never>?
    @ObservationIgnored var pendingPassword = ""
    @ObservationIgnored var reconnectPolicy = MumbleReconnectPolicy()
    @ObservationIgnored var reconnectTask: Task<Void, Never>?
    @ObservationIgnored var reconnectServerID: MumbleServer.ID?
    @ObservationIgnored var suppressReconnect = false
    @ObservationIgnored var didSynchronize = false

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoReconnectEnabled = defaults.object(forKey: "autoReconnectEnabled") as? Bool ?? true
    }

    func beginConnection(serverID: MumbleServer.ID, isReconnect: Bool) {
        if !isReconnect {
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectPolicy.reset()
            isReconnecting = false
            reconnectAttempt = 0
            reconnectServerID = serverID
        }
        suppressReconnect = false
        didSynchronize = false
        connectionTask?.cancel()
        pingTask?.cancel()
    }

    @discardableResult
    func markSynchronized() -> Bool {
        let wasReconnecting = isReconnecting
        didSynchronize = true
        reconnectPolicy.reset()
        isReconnecting = false
        reconnectAttempt = 0
        return wasReconnecting
    }

    func setAutoReconnectEnabled(_ enabled: Bool) {
        autoReconnectEnabled = enabled
        defaults.set(enabled, forKey: "autoReconnectEnabled")
        if !enabled {
            reconnectTask?.cancel()
            reconnectTask = nil
            isReconnecting = false
            reconnectAttempt = 0
        }
    }

    func prepareForLocalDisconnect() {
        suppressReconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        reconnectAttempt = 0
        reconnectPolicy.reset()
        connectionTask?.cancel()
        connectionTask = nil
        pingTask?.cancel()
        pingTask = nil
    }
}
