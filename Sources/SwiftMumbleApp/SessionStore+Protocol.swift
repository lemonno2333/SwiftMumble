import AppKit
import Foundation
import MumbleAudio
import MumbleProtocol
import MumbleSystem
extension SessionStore {
    func handle(_ frame: MumbleFrame) {
        do {
            if frame.type == .userState
                || (frame.type == .udpTunnel && audioPacketsReceived.isMultiple(of: 100)) {
                AudioDiagnostics.shared.record(
                    "control.receive type=\(frame.type) transmitting=\(isTransmitting)"
                )
            }
            if frame.type == .userState,
               case .connected(let ownSession) = connectionState {
                let state = try frame.decode(as: MumbleProto_UserState.self)
                if state.hasSession, state.hasComment || state.hasTexture {
                    requestedUserResourceSessions.remove(state.session)
                }
                if state.session == ownSession {
                    listeningChannelIDs.formUnion(state.listeningChannelAdd)
                    listeningChannelIDs.subtract(state.listeningChannelRemove)
                    for adjustment in state.listeningVolumeAdjustment {
                        listeningChannelVolumes[adjustment.listeningChannel] = adjustment.volumeAdjustment
                    }
                }
            }
            if frame.type == .version {
                serverProtocolVersion = MumbleProtocolVersion(
                    message: try frame.decode(as: MumbleProto_Version.self)
                )
                return
            }
            if frame.type == .ping {
                let ping = try frame.decode(as: MumbleProto_Ping.self)
                lastControlPongAt = Date()
                if ping.hasTimestamp {
                    lastControlPingMilliseconds = max(0, Date().timeIntervalSince1970 * 1_000 - Double(ping.timestamp))
                }
                return
            }

            if frame.type == .channelState {
                let state = try frame.decode(as: MumbleProto_ChannelState.self)
                if state.hasChannelID, state.hasDescription_p {
                    requestedChannelDescriptions.remove(state.channelID)
                } else if state.hasChannelID, state.hasDescriptionHash, !state.descriptionHash.isEmpty {
                    let channelID = state.channelID
                    if requestedChannelDescriptions.insert(channelID).inserted {
                        Task { try? await controlConnection.send(MumbleCommands.requestChannelDescription(channelID: channelID)) }
                    }
                }
            }

            if frame.type == .cryptSetup {
                try handleCryptSetup(frame)
                return
            }

            if frame.type == .udpTunnel {
                // Parse tunneled voice off the MainActor; a malformed voice
                // packet is dropped rather than treated as a fatal protocol
                // error. The serial queue preserves packet order.
                let ingress = audioIngress
                let payload = frame.payload
                tunnelAudioQueue.async { [weak self] in
                    guard let event = try? ingress.receive(payload: payload) else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.handleAudioIngressEvent(event) }
                    }
                }
                return
            }

            if frame.type == .reject {
                // Auth/version rejection won't fix itself by retrying.
                suppressReconnect = true
                let rejection = try frame.decode(as: MumbleProto_Reject.self)
                connectionState = .failed(
                    message: rejection.hasReason ? rejection.reason : L10n.text("connection.rejected")
                )
                return
            }

            if frame.type == .textMessage {
                let message = try frame.decode(as: MumbleProto_TextMessage.self)
                // Direct messages target specific sessions rather than a channel/tree.
                let isPrivate = !message.session.isEmpty
                    && message.channelID.isEmpty
                    && message.treeID.isEmpty
                let baseAuthor = message.hasActor ? userName(session: message.actor) : L10n.text("chat.server")
                let actorUser = message.hasActor ? findUser(session: message.actor, in: channels) : nil
                if let actorUser, isIgnoringMessages(from: actorUser) { return }
                let author = isPrivate ? L10n.text("chat.privateFrom", baseAuthor) : baseAuthor
                let plainText = MessageText.plainText(from: message.message)
                let isMention = ownUserName.map { MessageText.mentions(plainText, username: $0) } ?? false
                chat.append(
                    ChatEntry(
                        author: author,
                        timestamp: Date(),
                        text: message.message,
                        isLocal: false,
                        isPrivate: isPrivate,
                        isMention: isMention
                    )
                )
                refreshDockBadge()
                if notificationsEnabled, isPrivate {
                    MumbleNotificationService.post(
                        title: L10n.text("notifications.private.title", baseAuthor),
                        body: plainText
                    )
                } else if notificationsEnabled, isMention, !chat.isApplicationActive {
                    MumbleNotificationService.post(
                        title: L10n.text("notifications.mention.title", baseAuthor),
                        body: plainText
                    )
                }
                if textToSpeechEnabled, actorUser.map({ !isIgnoringTTS(from: $0) }) ?? true {
                    messageSpeechService.speak(
                        L10n.text("tts.message", baseAuthor, plainText)
                    )
                }
                return
            }

            if frame.type == .userStats {
                let statistics = MumbleUserStatistics(
                    message: try frame.decode(as: MumbleProto_UserStats.self)
                )
                if userInformationTarget?.id == statistics.session {
                    userStatistics = statistics
                    isLoadingUserStatistics = false
                }
                return
            }

            if frame.type == .acl {
                aclConfiguration = MumbleACLConfiguration(message: try frame.decode(as: MumbleProto_ACL.self))
                isLoadingACL = false
                return
            }
            if frame.type == .contextActionModify {
                let modify = try frame.decode(as: MumbleProto_ContextActionModify.self)
                if modify.operation == .remove { serverContextActions.removeAll { $0.action == modify.action } }
                else {
                    serverContextActions.removeAll { $0.action == modify.action }
                    serverContextActions.append(ServerContextAction(action: modify.action, title: modify.text, contexts: modify.context))
                }
                return
            }
            if frame.type == .suggestConfig {
                let suggestion = try frame.decode(as: MumbleProto_SuggestConfig.self)
                serverSuggestedPushToTalk = suggestion.hasPushToTalk ? suggestion.pushToTalk : nil
                serverSuggestedPositionalAudio = suggestion.hasPositional ? suggestion.positional : nil
                serverSuggestedVersion = suggestion.hasVersionV2 ? suggestion.versionV2
                    : (suggestion.hasVersionV1 ? UInt64(suggestion.versionV1) : nil)
                return
            }
            if frame.type == .serverConfig {
                let config = try frame.decode(as: MumbleProto_ServerConfig.self)
                if config.hasAllowHtml { serverAllowsHTML = config.allowHtml }
                if config.hasMessageLength, config.messageLength > 0 { serverMessageLengthLimit = Int(config.messageLength) }
                if config.hasImageMessageLength, config.imageMessageLength > 0 {
                    serverImageMessageLengthLimit = Int(config.imageMessageLength)
                }
                if config.hasWelcomeText { serverWelcomeText = config.welcomeText }
                if config.hasMaxUsers { serverMaximumUsers = config.maxUsers }
                if config.hasMaxBandwidth { serverMaximumBandwidth = config.maxBandwidth }
                if config.hasRecordingAllowed { serverRecordingAllowed = config.recordingAllowed }
                return
            }
            if frame.type == .userList {
                let list = try frame.decode(as: MumbleProto_UserList.self)
                registeredUsers = list.users.map {
                    MumbleRegisteredUser(id: $0.userID, name: $0.name, lastSeen: $0.lastSeen,
                                         lastChannelID: $0.hasLastChannel ? $0.lastChannel : nil)
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                isLoadingRegisteredUsers = false
                return
            }

            if frame.type == .permissionDenied {
                let denied = try frame.decode(as: MumbleProto_PermissionDenied.self)
                serverManagementError = denied.hasReason && !denied.reason.isEmpty
                    ? denied.reason
                    : L10n.text("permission.denied")
                return
            }

            let change = try protocolState.apply(frame)
            guard change != nil else { return }

            let snapshot = protocolState.snapshot()
            removeAudioPipelinesForDepartedUsers(from: channelSnapshot, to: snapshot.channels)
            if (notificationsEnabled || audioCuesEnabled), didSynchronize {
                notifyUserChanges(from: channelSnapshot, to: snapshot.channels, ownSession: snapshot.session)
            }
            channelSnapshot = snapshot.channels
            rebuildChannels()
            currentPermissions = snapshot.permissions ?? []
            let isSynchronize: Bool
            if case .synchronized = change { isSynchronize = true } else { isSynchronize = false }
            if isSynchronize { applyChannelExpansionPolicy() }
            serverWelcomeText = snapshot.welcomeText
            if let ownSession = snapshot.session {
                let ownUser = findUser(session: ownSession, in: snapshot.channels)
                let recognizedHash = ownUser?.certificateHash
                if recognizedHash != serverRecognizedIdentityHash, let recognizedHash {
                    identityLogger.notice("Murmur recognized client certificate hash: \(recognizedHash, privacy: .public)")
                }
                serverRecognizedIdentityHash = recognizedHash
                if let ownUser {
                    // On (re)synchronize the local self-mute/deafen intent is
                    // authoritative: a fresh server session always reports
                    // selfMute=false, so adopting it here would silently un-mute
                    // a user who muted before a reconnect and — in voice-activity
                    // or continuous mode — immediately resume live mic transmission.
                    // The .synchronized branch below pushes the retained local
                    // state to the server via reportSelfAudioState instead.
                    if !isSynchronize {
                        applyServerSelfState(ownUser)
                    }
                    trackOwnChannel(ownUser.channelID)
                }
            }
            if selectedChannelID == nil {
                selectedChannelID = snapshot.channels.first?.id
            }
            if case .synchronized(let session) = change {
                AudioDiagnostics.shared.record("connection.synchronized session=\(session)")
                connectionState = .connected(session: session)
                audioIngress.configure(ownSession: session, targetDelayFrames: jitterBufferDelayFrames)
                startAudioMixLoop()
                realtimeVoiceActivity.setTransmissionAllowed(!isMuted)
                let wasReconnecting = connectionCoordinator.markSynchronized()
                if notificationsEnabled {
                    MumbleNotificationService.post(
                        title: L10n.text(wasReconnecting ? "notifications.reconnected.title" : "notifications.connected.title"),
                        body: activeServer?.name ?? "Mumble"
                    )
                }
                if audioCuesEnabled { playAudioCue(.connected) }
                reportSelfAudioState(session: session)
                if wasReconnecting, let selectedChannelID {
                    Task {
                        try? await controlConnection.send(
                            MumbleCommands.joinChannel(session: session, channelID: selectedChannelID)
                        )
                    }
                }
                refreshAutomaticAudioCapture()
                if transmissionMode == .pushToTalk, !isMuted {
                    let capture = audioCapture
                    Task.detached(priority: .utility) { try? capture.prepare() }
                }
                joinPendingChannelPath()
            }
        } catch {
            connectionState = .failed(message: L10n.text("protocol.error", error.localizedDescription))
        }
    }

    func handleAudioIngressEvent(_ event: AudioIngressEvent) {
        if event.isSelfAudio {
            droppedSelfAudioPackets &+= 1
            if droppedSelfAudioPackets == 1 || droppedSelfAudioPackets.isMultiple(of: 100) {
                AudioDiagnostics.shared.record(
                    "receive.dropSelf count=\(droppedSelfAudioPackets) session=\(event.session)"
                )
            }
            return
        }
        recordAudioPacketReceived()
        if event.isNewSource { seedMixerSettings(session: event.session) }
        updateTalking(session: event.session, isTerminator: event.isTerminator)
    }

    func updateTalking(session: UInt32, isTerminator: Bool) {
        // Locally muted speakers should not appear as talking.
        let changed: Bool
        if isTerminator || locallyMutedSessions.contains(session) {
            changed = talkingTracker.clear(session: session)
        } else {
            changed = talkingTracker.markActive(
                session: session,
                now: ProcessInfo.processInfo.systemUptime
            )
            startTalkingPruneLoop()
        }
        if changed { publishTalkingSessions() }
    }

    func startTalkingPruneLoop() {
        guard talkingPruneTask == nil else { return }
        talkingPruneTask = Task {
            defer { talkingPruneTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                if talkingTracker.pruneExpired(now: ProcessInfo.processInfo.systemUptime) {
                    publishTalkingSessions()
                }
                if talkingTracker.talkingSessions.isEmpty { return }
            }
        }
    }

    /// Publishes the live speaking set. Only this small `Set` is observed by the
    /// user rows, so a talk edge no longer rebuilds the entire channel tree.
    func publishTalkingSessions() {
        var talking = talkingTracker.talkingSessions
        if isTransmitting, case .connected(let ownSession) = connectionState {
            talking.insert(ownSession)
        }
        if talking != talkingSessions { talkingSessions = talking }
    }

    /// Rebuilds the channel tree from the latest protocol snapshot. Called only
    /// on structural changes (join/leave/move/rename), not on talk edges.
    func rebuildChannels() {
        channels = channelSnapshot
    }

    func removeAudioPipeline(session: UInt32) {
        audioIngress.remove(session: session)
        if talkingTracker.clear(session: session) { publishTalkingSessions() }
    }

    func removeAudioPipelinesForDepartedUsers(
        from oldChannels: [MumbleChannel],
        to newChannels: [MumbleChannel]
    ) {
        let oldSessions = Set(allUsers(in: oldChannels).map(\.id))
        let newSessions = Set(allUsers(in: newChannels).map(\.id))
        for session in oldSessions.subtracting(newSessions) {
            AudioDiagnostics.shared.record("drain.userRemoved session=\(session)")
            removeAudioPipeline(session: session)
        }
    }

    func startAudioMixLoop() {
        do {
            let playback = try ensureAudioPlayback()
            playback.setMuted(isDeafened)
            audioIngress.startMixClock(playback: playback, referenceSink: inputProcessor)
        } catch {
            audioErrorMessage = error.localizedDescription
        }
    }

    func handleCryptSetup(_ frame: MumbleFrame) throws {
        let setup = try frame.decode(as: MumbleProto_CryptSetup.self)
        if setup.hasKey, setup.hasClientNonce, setup.hasServerNonce {
            let state = try MumbleCryptState(
                key: setup.key,
                clientNonce: setup.clientNonce,
                serverNonce: setup.serverNonce
            )
            if let server = activeServer {
                startUDP(host: server.host, port: server.port, cryptState: state)
            }
            self.cryptState = state
        } else if setup.hasServerNonce, let cryptState {
            try cryptState.updateServerNonce(setup.serverNonce)
        } else if let cryptState {
            var response = MumbleProto_CryptSetup()
            response.clientNonce = cryptState.clientNonce
            Task {
                if let frame = try? MumbleFrame(type: .cryptSetup, message: response) {
                    try? await controlConnection.send(frame)
                }
            }
        }
    }

    func startUDP(host: String, port: UInt16, cryptState: MumbleCryptState) {
        let realtimeVoiceRouter = voiceRouter
        guard proxyType == .none else {
            isUsingUDP = false
            realtimeVoiceRouter.configureUDP(nil)
            return
        }
        stopUDP()
        let udpConnection = MumbleUDPConnection(
            cryptState: cryptState,
            diagnosticsHandler: { AudioDiagnostics.shared.record($0) }
        )
        self.udpConnection = udpConnection
        realtimeVoiceRouter.configureUDP(udpConnection)
        // Baseline for both the TCP-fallback timeout and crypt-resync
        // staleness until the first packet decrypts.
        lastUDPResponseAt = Date()
        lastCryptResyncRequestAt = nil

        let ingress = audioIngress
        let protocolVersion = serverProtocolVersion
        udpTask = Task.detached(priority: .high) { [weak self] in
            let events = await udpConnection.connect(host: host, port: port)
            for await event in events {
                guard !Task.isCancelled else { return }
                switch event {
                case .ready:
                    await self?.startUDPPingLoop(udpConnection)
                case .packet(let packet):
                    if (try? MumbleUDPPacket.pingTimestamp(
                        from: packet,
                        protocolVersion: protocolVersion
                    )) != nil {
                        realtimeVoiceRouter.setUDPAvailable(true)
                        await self?.markUDPActive()
                    } else {
                        realtimeVoiceRouter.setUDPAvailable(true)
                        do {
                            let audioEvent = try ingress.receive(payload: packet)
                            DispatchQueue.main.async { [weak self] in
                                MainActor.assumeIsolated {
                                    self?.markUDPActive(audioByteCount: packet.count)
                                    self?.handleAudioIngressEvent(audioEvent)
                                }
                            }
                        } catch {
                            await self?.reportAudioIngressError(error.localizedDescription)
                        }
                    }
                case .failed:
                    realtimeVoiceRouter.setUDPAvailable(false)
                    await self?.markUDPInactive()
                case .disconnected:
                    realtimeVoiceRouter.setUDPAvailable(false)
                    await self?.markUDPInactive()
                }
                await Task.yield()
            }
        }
    }

    func markUDPActive(audioByteCount: Int? = nil) {
        if let audioByteCount, audioPacketsReceived.isMultiple(of: 100) {
            AudioDiagnostics.shared.record(
                "udp.receive bytes=\(audioByteCount) transmitting=\(isTransmitting)"
            )
        }
        lastUDPResponseAt = Date()
        // Avoid re-assigning the observed property at packet rate.
        if !isUsingUDP { isUsingUDP = true }
    }

    func markUDPInactive() {
        isUsingUDP = false
    }

    func reportAudioIngressError(_ message: String) {
        audioErrorMessage = message
    }

    func startUDPPingLoop(_ udpConnection: MumbleUDPConnection) {
        guard proxyType == .none else { return }
        udpPingTask?.cancel()
        udpPingTask = Task {
            var lastRejectedCount = udpConnection.rejectedPacketCount
            while !Task.isCancelled {
                do {
                    let timestamp = UInt64(Date().timeIntervalSince1970 * 1_000)
                    try await udpConnection.send(
                        MumbleUDPPacket.ping(
                            timestamp: timestamp,
                            protocolVersion: serverProtocolVersion
                        )
                    )
                    try await Task.sleep(for: .seconds(5))
                    if let lastUDPResponseAt,
                       Date().timeIntervalSince(lastUDPResponseAt) > 12 {
                        isUsingUDP = false
                        voiceRouter.setUDPAvailable(false)
                    }
                    // Undecryptable packets arriving while nothing decrypts is
                    // the signature of OCB2 nonce desynchronization. Ask the
                    // server to re-send its nonce so voice recovers without a
                    // reconnect (matches official client behavior). A silent
                    // socket (UDP blocked) does not trigger requests.
                    let rejectedCount = udpConnection.rejectedPacketCount
                    let rejectsAdvanced = rejectedCount > lastRejectedCount
                    lastRejectedCount = rejectedCount
                    if rejectsAdvanced,
                       let lastGood = lastUDPResponseAt,
                       cryptResyncPolicy.shouldRequestResync(
                        lastGoodAt: lastGood,
                        lastRequestAt: lastCryptResyncRequestAt,
                        now: Date()
                       ) {
                        lastCryptResyncRequestAt = Date()
                        AudioDiagnostics.shared.record("crypt.resyncRequested rejected=\(rejectedCount)")
                        if let frame = try? MumbleCommands.requestCryptResync() {
                            try? await controlConnection.send(frame)
                        }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    isUsingUDP = false
                    voiceRouter.setUDPAvailable(false)
                    return
                }
            }
        }
    }

    func stopUDP() {
        udpTask?.cancel()
        udpTask = nil
        udpPingTask?.cancel()
        udpPingTask = nil
        isUsingUDP = false
        lastUDPResponseAt = nil
        lastCryptResyncRequestAt = nil
        cryptState = nil
        if let udpConnection {
            Task { await udpConnection.disconnect() }
        }
        udpConnection = nil
        voiceRouter.configureUDP(nil)
    }

    func selectInputDevice(_ deviceID: UInt32?) {
        let restartMonitoring = isMicrophoneMonitoring
        if restartMonitoring { stopAutomaticAudioCapture() }
        selectedInputDeviceID = deviceID
        audioCapture.selectDevice(deviceID)
        saveDeviceSelection(deviceID, key: "selectedInputDeviceID")
        if restartMonitoring { refreshAutomaticAudioCapture() }
    }

    func selectOutputDevice(_ deviceID: UInt32?) {
        selectedOutputDeviceID = deviceID
        do {
            try audioPlayback?.selectDevice(deviceID)
            saveDeviceSelection(deviceID, key: "selectedOutputDeviceID")
        } catch {
            audioErrorMessage = error.localizedDescription
        }
    }

    func saveDeviceSelection(_ deviceID: UInt32?, key: String) {
        if let deviceID { UserDefaults.standard.set(NSNumber(value: deviceID), forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    func startPingLoop() {
        pingTask?.cancel()
        lastControlPongAt = Date()
        pingTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(controlPingIntervalSeconds))
                    // The server answers every ping; if several intervals pass
                    // with no pong the control socket is dead even though TCP
                    // hasn't reported an error yet (NAT/Wi-Fi idle drop). Tear
                    // down proactively so auto-reconnect can take over instead
                    // of leaving the UI stuck on a frozen "Connected" state.
                    if let lastControlPongAt,
                       Date().timeIntervalSince(lastControlPongAt) > deadConnectionTimeoutSeconds {
                        AudioDiagnostics.shared.record("connection.deadNoPong")
                        handleDeadControlConnection()
                        return
                    }
                    var ping = MumbleProto_Ping()
                    ping.timestamp = UInt64(Date().timeIntervalSince1970 * 1_000)
                    try await controlConnection.send(MumbleFrame(type: .ping, message: ping))
                } catch is CancellationError {
                    return
                } catch {
                    connectionState = .failed(message: L10n.text("connection.pingError", error.localizedDescription))
                    return
                }
            }
        }
    }

    /// The control channel stopped responding to pings. Treat it like a
    /// transport failure: drop media and let the reconnect policy retry.
    private func handleDeadControlConnection() {
        connectionState = .failed(message: L10n.text("connection.timedOut"))
        pingTask?.cancel()
        stopMediaForConnectionLoss()
        scheduleReconnectIfNeeded()
        Task { await controlConnection.disconnect() }
    }

    /// Number of seconds without a ping response before the control connection
    /// is considered dead. Three ping intervals gives generous slack for a
    /// briefly stalled link while still reacting within ~a minute at defaults.
    var deadConnectionTimeoutSeconds: TimeInterval {
        TimeInterval(controlPingIntervalSeconds) * 3 + 5
    }

    func findChannel(id: UInt32, in channels: [MumbleChannel]) -> MumbleChannel? {
        for channel in channels {
            if channel.id == id { return channel }
            if let match = findChannel(id: id, in: channel.children) { return match }
        }
        return nil
    }

    var ownUserName: String? {
        guard case .connected(let session) = connectionState else { return nil }
        return findUser(session: session, in: channels)?.name
    }

    // MARK: - Unread state

    func refreshDockBadge() {
        let count = chat.unreadCount
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }

    /// Called from the app delegate on active/inactive transitions.
    func applicationActivityChanged(isActive: Bool) {
        chat.isApplicationActive = isActive
        if isActive {
            chat.markRead()
            refreshDockBadge()
        }
    }
}
