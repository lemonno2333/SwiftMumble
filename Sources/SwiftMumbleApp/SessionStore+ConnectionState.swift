import Foundation
import MumbleProtocol

extension SessionStore {
    var autoReconnectEnabled: Bool {
        get { connectionCoordinator.autoReconnectEnabled }
        set { connectionCoordinator.autoReconnectEnabled = newValue }
    }

    var isReconnecting: Bool {
        get { connectionCoordinator.isReconnecting }
        set { connectionCoordinator.isReconnecting = newValue }
    }

    var reconnectAttempt: Int {
        get { connectionCoordinator.reconnectAttempt }
        set { connectionCoordinator.reconnectAttempt = newValue }
    }

    var connectionTask: Task<Void, Never>? {
        get { connectionCoordinator.connectionTask }
        set { connectionCoordinator.connectionTask = newValue }
    }

    var teardownTask: Task<Void, Never>? {
        get { connectionCoordinator.teardownTask }
        set { connectionCoordinator.teardownTask = newValue }
    }

    var pingTask: Task<Void, Never>? {
        get { connectionCoordinator.pingTask }
        set { connectionCoordinator.pingTask = newValue }
    }

    var pendingConnectionPassword: String {
        get { connectionCoordinator.pendingPassword }
        set { connectionCoordinator.pendingPassword = newValue }
    }

    var reconnectPolicy: MumbleReconnectPolicy {
        get { connectionCoordinator.reconnectPolicy }
        set { connectionCoordinator.reconnectPolicy = newValue }
    }

    var reconnectTask: Task<Void, Never>? {
        get { connectionCoordinator.reconnectTask }
        set { connectionCoordinator.reconnectTask = newValue }
    }

    var reconnectServerID: MumbleServer.ID? {
        get { connectionCoordinator.reconnectServerID }
        set { connectionCoordinator.reconnectServerID = newValue }
    }

    var suppressReconnect: Bool {
        get { connectionCoordinator.suppressReconnect }
        set { connectionCoordinator.suppressReconnect = newValue }
    }

    var didSynchronize: Bool {
        get { connectionCoordinator.didSynchronize }
        set { connectionCoordinator.didSynchronize = newValue }
    }
}
