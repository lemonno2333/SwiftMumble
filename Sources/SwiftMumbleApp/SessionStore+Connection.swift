import AppKit
import Foundation
import MumbleAudio
import MumbleProtocol
import MumbleSystem
extension SessionStore {
    func connect(password: String? = nil, isReconnect: Bool = false) {
        let server = isReconnect
            ? reconnectServerID.flatMap { id in servers.first { $0.id == id } }
            : selectedServer
        guard let server else {
            connectionState = .failed(message: L10n.text("server.selectFirst"))
            return
        }

        connectionCoordinator.beginConnection(serverID: server.id, isReconnect: isReconnect)
        if serverRepository.beginSession(serverID: server.id) { selectedServerDidChange() }
        protocolState = MumbleServerState()
        requestedChannelDescriptions.removeAll()
        requestedUserResourceSessions.removeAll()
        serverContextActions = []
        serverSuggestedPushToTalk = nil
        serverSuggestedPositionalAudio = nil
        serverSuggestedVersion = nil
        stopUDP()
        serverProtocolVersion = MumbleProtocolVersion(major: 1, minor: 4, patch: 0)
        channels = []
        serverWelcomeText = ""
        chat.beginConnection(isReconnect: isReconnect)
        serverRecognizedIdentityHash = nil
        connectionState = .connecting
        AudioDiagnostics.shared.record("connection.begin host=\(server.host) mode=\(transmissionMode.rawValue)")

        let resolvedPassword = password
            ?? (try? KeychainPasswordStore.load(account: server.id.uuidString))
            ?? ""
        let username = server.username.isEmpty ? NSUserName() : server.username
        let accessTokens = (try? KeychainAccessTokenStore.load(account: server.id.uuidString)) ?? []
        let credentials = MumbleCredentials(
            username: username,
            password: resolvedPassword,
            tokens: accessTokens
        )
        pendingConnectionPassword = resolvedPassword

        let pinnedFingerprint: MumbleCertificateFingerprint?
        if let configuredFingerprint = server.certificateFingerprint,
           !configuredFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let parsed = MumbleCertificateFingerprint(hex: configuredFingerprint) else {
                suppressReconnect = true
                connectionState = .failed(message: L10n.text("certificate.fingerprint.invalid"))
                Task { await controlConnection.disconnect() }
                return
            }
            pinnedFingerprint = parsed
        } else {
            pinnedFingerprint = nil
        }

        let pendingTeardown = teardownTask
        teardownTask = nil
        connectionTask = Task {
            // Order teardown before the new socket: a prior disconnect()'s
            // control-connection teardown must complete first, or it could
            // cancel this freshly opened connection.
            await pendingTeardown?.value
            guard !Task.isCancelled else { return }
            let events = await controlConnection.connect(
                host: server.host,
                port: server.port,
                pinnedCertificateSHA256: pinnedFingerprint?.bytes,
                clientIdentity: clientIdentity,
                connectionTimeoutSeconds: UInt32(connectionTimeoutSeconds),
                proxy: proxyConfiguration
            )

            for await event in events {
                guard !Task.isCancelled else { return }

                switch event {
                case .preparing:
                    AudioDiagnostics.shared.record("connection.preparing")
                    connectionState = .connecting

                case .ready:
                    AudioDiagnostics.shared.record("connection.ready")
                    connectionState = .authenticating
                    do {
                        for frame in try MumbleHandshake.frames(credentials: credentials) {
                            try await controlConnection.send(frame)
                        }
                        startPingLoop()
                    } catch {
                        connectionState = .failed(message: error.localizedDescription)
                        await controlConnection.disconnect()
                    }

                case .frame(let frame):
                    handle(frame)

                case .waiting(let message):
                    connectionState = .failed(message: message)

                case .untrustedCertificate(let subject, let fingerprint):
                    // Needs user approval; never auto-reconnect into the same wall.
                    suppressReconnect = true
                    pendingServerCertificate = PendingServerCertificate(
                        serverID: server.id,
                        host: server.host,
                        subject: subject,
                        fingerprint: fingerprint,
                        previousFingerprint: nil
                    )
                    connectionState = .failed(message: L10n.text("certificate.confirmRequired"))

                case .certificateMismatch(let subject, let expected, let actual):
                    suppressReconnect = true
                    pendingServerCertificate = PendingServerCertificate(
                        serverID: server.id,
                        host: server.host,
                        subject: subject,
                        fingerprint: actual,
                        previousFingerprint: expected
                    )
                    connectionState = .failed(message: L10n.text("certificate.confirmRequired"))

                case .failed(let message):
                    if pendingServerCertificate == nil {
                        connectionState = .failed(message: message)
                    }
                    pingTask?.cancel()
                    stopMediaForConnectionLoss()
                    scheduleReconnectIfNeeded()

                case .disconnected:
                    AudioDiagnostics.shared.record("connection.disconnected")
                    pingTask?.cancel()
                    stopMediaForConnectionLoss()
                    if case .failed = connectionState {
                        scheduleReconnectIfNeeded()
                        break
                    }
                    connectionState = .disconnected
                    if notificationsEnabled, didSynchronize {
                        MumbleNotificationService.post(
                            title: L10n.text("notifications.disconnected.title"),
                            body: server.name
                        )
                    }
                    if audioCuesEnabled, didSynchronize { playAudioCue(.disconnected) }
                    scheduleReconnectIfNeeded()
                }
                await Task.yield()
            }
        }
    }

    func handleServerDoubleClick(_ server: MumbleServer) {
        switch connectionState {
        case .connecting, .authenticating, .connected:
            return
        case .disconnected, .failed:
            connect(to: server)
        }
    }

    func openMumbleURL(_ url: URL) {
        guard let target = MumbleURL(url: url) else {
            serverManagementError = L10n.text("server.url.invalid")
            return
        }
        let server: MumbleServer
        if let existing = servers.first(where: { $0.host.caseInsensitiveCompare(target.host) == .orderedSame && $0.port == target.port }) {
            server = existing
        } else {
            server = MumbleServer(name: target.host, host: target.host, port: target.port, username: target.username ?? "")
            serverRepository.add(server)
        }
        pendingChannelPath = target.channelPath
        connect(to: server)
    }

    func serverURL() -> URL? {
        guard let server = selectedServer else { return nil }
        return MumbleURL(host: server.host, port: server.port, username: server.username).url
    }

    func serverURL(for server: MumbleServer) -> URL? {
        MumbleURL(host: server.host, port: server.port, username: server.username).url
    }

    func channelURL(_ channel: MumbleChannel) -> URL? {
        guard let server = activeServer ?? selectedServer else { return nil }
        return MumbleURL(host: server.host, port: server.port, username: server.username, channelPath: path(to: channel.id)).url
    }

    func copyURL(_ url: URL?) {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func connectToDiscoveredServer(_ discovered: DiscoveredMumbleServer) {
        let server: MumbleServer
        if let existing = servers.first(where: { $0.host == discovered.host && $0.port == discovered.port }) {
            server = existing
        } else {
            server = MumbleServer(name: discovered.name, host: discovered.host, port: discovered.port)
            serverRepository.add(server)
        }
        connect(to: server)
    }

    func setPublicServerDirectoryEnabled(_ enabled: Bool) {
        publicServerDirectoryEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "publicServerDirectoryEnabled")
        if enabled { refreshPublicServers() }
        else { publicServers = []; publicServerError = nil }
    }

    func setConnectionTimeoutSeconds(_ seconds: Int) {
        connectionTimeoutSeconds = min(120, max(5, seconds))
        UserDefaults.standard.set(connectionTimeoutSeconds, forKey: "connectionTimeoutSeconds")
    }

    func setControlPingIntervalSeconds(_ seconds: Int) {
        controlPingIntervalSeconds = min(60, max(5, seconds))
        UserDefaults.standard.set(controlPingIntervalSeconds, forKey: "controlPingIntervalSeconds")
        if case .connected = connectionState { startPingLoop() }
    }

    var proxyConfiguration: MumbleProxyConfiguration {
        MumbleProxyConfiguration(type: proxyType, host: proxyHost, port: proxyPort, username: proxyUsername,
                                 password: (try? KeychainPasswordStore.load(account: "network-proxy")) ?? "")
    }

    func saveProxy(type: MumbleProxyType, host: String, port: UInt16, username: String, password: String) {
        proxyType = type; proxyHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        proxyPort = port; proxyUsername = username
        let defaults = UserDefaults.standard
        defaults.set(type.rawValue, forKey: "proxyType"); defaults.set(proxyHost, forKey: "proxyHost")
        defaults.set(Int(port), forKey: "proxyPort"); defaults.set(username, forKey: "proxyUsername")
        if password.isEmpty { try? KeychainPasswordStore.delete(account: "network-proxy") }
        else { try? KeychainPasswordStore.save(password, account: "network-proxy") }
        if type != .none { stopUDP() }
    }

    func refreshPublicServers() {
        guard publicServerDirectoryEnabled, !isLoadingPublicServers else { return }
        isLoadingPublicServers = true; publicServerError = nil
        Task {
            do { publicServers = try await PublicServerDirectory.fetch() }
            catch { publicServerError = error.localizedDescription }
            isLoadingPublicServers = false
        }
    }

    func connectToPublicServer(_ publicServer: PublicMumbleServer) {
        let discovered = DiscoveredMumbleServer(name: publicServer.name, host: publicServer.host, port: publicServer.port)
        connectToDiscoveredServer(discovered)
    }

    func pingVisiblePublicServers() {
        guard publicServerDirectoryEnabled, !isPingingPublicServers else { return }
        isPingingPublicServers = true
        Task {
            await withTaskGroup(of: (String, ServerPingResult?).self) { group in
                for server in publicServers.prefix(50) {
                    group.addTask {
                        (server.id, try? await ServerPingService.ping(host: server.host, port: server.port))
                    }
                }
                for await (id, result) in group { if let result { publicServerPingResults[id] = result } }
            }
            isPingingPublicServers = false
        }
    }

    func requestChannelDescription(_ channel: MumbleChannel) {
        guard channel.descriptionText.isEmpty,
              requestedChannelDescriptions.insert(channel.id).inserted,
              case .connected = connectionState else { return }
        Task {
            do { try await controlConnection.send(MumbleCommands.requestChannelDescription(channelID: channel.id)) }
            catch { requestedChannelDescriptions.remove(channel.id) }
        }
    }

    func path(to channelID: UInt32) -> [String] {
        var names: [String] = []
        var current = flattenedChannels.first { $0.id == channelID }
        while let channel = current, channel.parentID != nil {
            names.insert(channel.name, at: 0)
            current = channel.parentID.flatMap { id in flattenedChannels.first { $0.id == id } }
        }
        return names
    }

    func joinPendingChannelPath() {
        guard !pendingChannelPath.isEmpty, case .connected(let session) = connectionState else { return }
        var candidates = channels
        var match: MumbleChannel?
        for component in pendingChannelPath {
            guard let next = candidates.first(where: { $0.name.caseInsensitiveCompare(component) == .orderedSame }) else { return }
            match = next
            candidates = next.children
        }
        guard let match else { return }
        pendingChannelPath = []
        selectedChannelID = match.id
        Task { try? await controlConnection.send(MumbleCommands.joinChannel(session: session, channelID: match.id)) }
    }

    func addServer(
        _ server: MumbleServer,
        password: String,
        savePassword: Bool,
        accessTokens: [String] = []
    ) {
        serverRepository.add(server)
        if activeServerID == nil, serverRepository.forceSelect(server.id) { selectedServerDidChange() }
        if savePassword, !password.isEmpty {
            do {
                try KeychainPasswordStore.save(password, account: server.id.uuidString)
            } catch {
                connectionState = .failed(message: L10n.text("keychain.saveError", error.localizedDescription))
            }
        }
        updateStoredAccessTokens(for: server.id, tokens: accessTokens)
    }

    func updateServer(
        _ server: MumbleServer,
        password: String,
        savePassword: Bool,
        accessTokens: [String] = []
    ) {
        guard servers.contains(where: { $0.id == server.id }) else { return }

        if activeServerID == server.id, connectionState != .disconnected {
            disconnect()
        }

        serverRepository.update(server)
        updateStoredPassword(for: server.id, password: password, shouldSave: savePassword)
        updateStoredAccessTokens(for: server.id, tokens: accessTokens)
    }

    func deleteServer(_ server: MumbleServer) {
        if activeServerID == server.id {
            disconnect()
        }

        serverRepository.remove(id: server.id)
        if serverRepository.forceSelect(servers.first?.id) { selectedServerDidChange() }
        pendingServerDeletion = nil

        do {
            try KeychainPasswordStore.delete(account: server.id.uuidString)
            try KeychainAccessTokenStore.delete(account: server.id.uuidString)
        } catch {
            serverManagementError = L10n.text("keychain.deleteAfterServerError", error.localizedDescription)
        }
    }

    func regenerateClientIdentity() {
        disconnect()
        do {
            let handle = try ClientIdentityStore.regenerate()
            clientIdentity = MumbleTLSClientIdentity(handle.identity)
            clientIdentityInfo = handle.info
            clientIdentityError = nil
        } catch {
            clientIdentity = nil
            clientIdentityInfo = nil
            clientIdentityError = L10n.text("identity.generateError", error.localizedDescription)
        }
    }

    func exportClientIdentity(passphrase: String) throws -> Data {
        try ClientIdentityStore.exportPKCS12(passphrase: passphrase)
    }

    func importClientIdentity(_ data: Data, passphrase: String) throws {
        disconnect()
        let handle = try ClientIdentityStore.importPKCS12(data, passphrase: passphrase)
        clientIdentity = MumbleTLSClientIdentity(handle.identity)
        clientIdentityInfo = handle.info
        clientIdentityError = nil
        serverRecognizedIdentityHash = nil
    }

    func retryClientIdentity() {
        loadClientIdentity()
    }

    func loadClientIdentity() {
        do {
            let handle = try ClientIdentityStore.loadOrCreate()
            clientIdentity = MumbleTLSClientIdentity(handle.identity)
            clientIdentityInfo = handle.info
            clientIdentityError = nil
        } catch {
            clientIdentity = nil
            clientIdentityInfo = nil
            clientIdentityError = L10n.text("identity.generateError", error.localizedDescription)
        }
    }

    func updateStoredPassword(
        for serverID: MumbleServer.ID,
        password: String,
        shouldSave: Bool
    ) {
        do {
            if shouldSave, !password.isEmpty {
                try KeychainPasswordStore.save(password, account: serverID.uuidString)
            } else {
                try KeychainPasswordStore.delete(account: serverID.uuidString)
            }
        } catch {
            serverManagementError = L10n.text("keychain.updateError", error.localizedDescription)
        }
    }

    func updateStoredAccessTokens(for serverID: MumbleServer.ID, tokens: [String]) {
        do {
            try KeychainAccessTokenStore.save(tokens, account: serverID.uuidString)
        } catch {
            serverManagementError = L10n.text("keychain.tokensUpdateError", error.localizedDescription)
        }
    }

    func trustPendingServerCertificate() {
        guard let pendingServerCertificate,
              let server = serverRepository.updateCertificateFingerprint(
                  pendingServerCertificate.fingerprint.hex,
                  serverID: pendingServerCertificate.serverID
              ) else {
            return
        }
        self.pendingServerCertificate = nil
        connect(to: server, password: pendingConnectionPassword)
    }

    func cancelPendingServerCertificate() {
        pendingServerCertificate = nil
        disconnect()
    }

    func disconnect() {
        prepareLocalDisconnect()
        // Track the teardown so a follow-on connect() (e.g. switching servers,
        // regenerating identity) can await it before opening the new socket.
        // Without ordering, this unstructured task can land on the control
        // connection actor *after* the new connect and cancel it.
        teardownTask = Task { await controlConnection.disconnect() }
    }

    func prepareLocalDisconnect() {
        AudioDiagnostics.shared.record("connection.disconnect requested")
        realtimeVoiceActivity.setTransmissionAllowed(false)
        cancelAudioLoopbackTest()
        // User-initiated: stop any pending reconnect and don't schedule new ones.
        connectionCoordinator.prepareForLocalDisconnect()
        stopAutomaticAudioCapture()
        endTransmission()
        audioCapture.shutdown()
        stopUDP()
        audioIngress.stopMixClock()
        audioPlayback?.stop()
        audioPlayback = nil
        audioIngress.removeAll()
        userVolumeGains.removeAll()
        locallyMutedSessions.removeAll()
        talkingPruneTask?.cancel()
        talkingPruneTask = nil
        talkingTracker.reset()
        channelSnapshot = []
        channelHistory.reset()
        listeningChannelIDs.removeAll()
        listeningChannelVolumes.removeAll()
        requestedChannelDescriptions.removeAll()
        requestedUserResourceSessions.removeAll()
        clearDisconnectedSessionPresentation()
        connectionState = .disconnected
        serverRepository.endSession()
        loadChannelPreferences()
        applyShortcutConfigurationForSelectedServer()
        refreshAutomaticAudioCapture()
    }

    func clearDisconnectedSessionPresentation() {
        protocolState = MumbleServerState()
        channels = []
        selectedChannelID = nil
        expandedChannelIDs.removeAll()
        serverWelcomeText = ""
        chat.clearSession()
        closeUserInformation()
        profileEditorTarget = nil
        moderationRequest = nil
        aclEditorChannel = nil
        aclConfiguration = nil
        registeredUsers.removeAll()
        serverContextActions.removeAll()
        serverRecognizedIdentityHash = nil
        serverSuggestedPushToTalk = nil
        serverSuggestedPositionalAudio = nil
        serverSuggestedVersion = nil
        lastControlPingMilliseconds = nil
        lastControlPongAt = nil
        serverMaximumUsers = nil
        serverMaximumBandwidth = nil
    }

    func stopMediaForConnectionLoss() {
        realtimeVoiceActivity.setTransmissionAllowed(false)
        stopAutomaticAudioCapture()
        endTransmission()
        audioCapture.shutdown()
        stopUDP()
        audioIngress.stopMixClock()
        audioPlayback?.stop()
        audioPlayback = nil
        audioIngress.removeAll()
        // Session-ID-keyed live preferences must not survive the connection: on
        // reconnect the server reuses session IDs, and seedMixerSettings gives a
        // stale live entry priority over the correct persisted (cert-hash-keyed)
        // value, so an old user's volume/mute would leak onto a new speaker.
        // The persisted-by-hash preferences remain and re-seed the fresh session.
        userVolumeGains.removeAll()
        locallyMutedSessions.removeAll()
        talkingPruneTask?.cancel()
        talkingPruneTask = nil
        talkingTracker.reset()
        publishTalkingSessions()
    }

    /// A control-command send failed. The TLS control channel is the same socket
    /// the whole session rides on, so a send error means the connection is gone —
    /// surface `.failed`, tear down the still-running media, and let the reconnect
    /// policy decide. Previously only chat send did this; other commands set
    /// `.failed` alone and left capture/playback running for ~65s until ping
    /// timeout noticed the dead socket.
    func handleCommandSendFailure(_ message: String) {
        connectionState = .failed(message: message)
        stopMediaForConnectionLoss()
        scheduleReconnectIfNeeded()
    }
}
