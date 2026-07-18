import AppKit
import Foundation
import MumbleAudio
import MumbleProtocol
import MumbleSystem
extension SessionStore {
    func beginTransmission() {
        cancelAudioLoopbackTest()
        pushToTalkReleaseTask?.cancel()
        pushToTalkReleaseTask = nil
        guard transmissionMode == .pushToTalk else { return }
        guard !isTransmitting, !isMuted else { return }
        guard case .connected = connectionState else { return }

        setTransmitting(true)
        audioErrorMessage = nil
        manualCaptureGeneration += 1
        let generation = manualCaptureGeneration

        manualCaptureTask = Task {
            let permissionGranted = await AudioCaptureService.requestMicrophonePermission()
            guard !Task.isCancelled,
                  transmissionMode == .pushToTalk,
                  isTransmitting,
                  generation == manualCaptureGeneration,
                  !isMuted,
                  case .connected = connectionState else { return }
            guard permissionGranted else {
                setTransmitting(false)
                audioErrorMessage = L10n.text("audio.permissionDenied")
                manualCaptureTask = nil
                return
            }

            do {
                audioCapture.selectDevice(selectedInputDeviceID)
                let frameStream = AsyncStream.makeStream(
                    of: [Float].self,
                    bufferingPolicy: .bufferingNewest(8)
                )
                manualFrameContinuation = frameStream.continuation
                let frameContinuation = frameStream.continuation
                let processor = inputProcessor
                let enqueueVoice = makeRealtimeVoiceEnqueuer()
                // Transmitted speech must not drop frames under load: this
                // loop only forwards to dedicated DSP/Opus queues, and the
                // per-packet MainActor work it used to compete with is now
                // batched, so it runs at high priority like the VAD path.
                manualFrameConsumerTask = Task.detached(priority: .high) {
                    var frameCount: UInt64 = 0
                    for await samples in frameStream.stream {
                        if Task.isCancelled { return }
                        frameCount &+= 1
                        let processed = await processor.processRealtime(samples)
                        enqueueVoice(processed)
                        if frameCount == 1 || frameCount.isMultiple(of: 100) {
                            AudioDiagnostics.shared.record(
                                "ptt.frame count=\(frameCount)"
                            )
                        }
                        await Task.yield()
                    }
                }
                try audioCapture.start { samples in
                    frameContinuation.yield(samples)
                }
                audioPlayback?.undoSystemVoiceDucking()
            } catch {
                manualFrameContinuation?.finish()
                manualFrameContinuation = nil
                manualFrameConsumerTask?.cancel()
                manualFrameConsumerTask = nil
                setTransmitting(false)
                audioErrorMessage = error.localizedDescription
            }
            manualCaptureTask = nil
        }
    }

    func endTransmission() {
        manualCaptureGeneration += 1
        pushToTalkReleaseTask?.cancel()
        pushToTalkReleaseTask = nil
        manualCaptureTask?.cancel()
        manualCaptureTask = nil
        if transmissionMode == .pushToTalk { audioCapture.stop() }
        manualFrameContinuation?.finish()
        manualFrameContinuation = nil
        manualFrameConsumerTask?.cancel()
        manualFrameConsumerTask = nil
        finishTransmitPipeline()
    }

    func releasePushToTalk() {
        guard transmissionMode == .pushToTalk else {
            endTransmission()
            return
        }
        pushToTalkReleaseTask?.cancel()
        let hold = PushToTalkHoldConfiguration(milliseconds: pushToTalkHoldMilliseconds)
        guard hold.milliseconds > 0 else {
            endTransmission()
            return
        }
        pushToTalkReleaseTask = Task {
            do {
                try await Task.sleep(for: hold.duration)
                guard !Task.isCancelled else { return }
                pushToTalkReleaseTask = nil
                endTransmission()
            } catch is CancellationError {
                return
            } catch {
                endTransmission()
            }
        }
    }

    func toggleLatchedPushToTalk() {
        guard transmissionMode == .pushToTalk else { return }
        if isTransmitting { endTransmission() } else { beginTransmission() }
    }

    func finishTransmitPipeline() {
        guard isTransmitting else { return }
        publishPendingAudioPacketCount()
        setTransmitting(false)
        let voiceRouter = voiceRouter
        let target = activeVoiceTargetID
        let protocolVersion = serverProtocolVersion
        transmitEncodingQueue.finish { frameNumber in
            guard let frameNumber else { return }
            if let packet = try? MumbleVoicePacket.clientAudioPacket(
                opusData: Data(),
                frameNumber: frameNumber,
                target: target,
                isTerminator: true,
                protocolVersion: protocolVersion
            ) {
                voiceRouter.enqueue(packet)
            }
        }
        activeVoiceTargetID = 0
    }

    func sendCapturedFrame(_ samples: [Float], alreadyProcessed: Bool = false) {
        let samples = alreadyProcessed ? samples : inputProcessor.process(samples)
        if !isTransmitting { setTransmitting(true) }
        let configuration = opusEncoderConfiguration
        let framesPerPacket = opusFramesPerPacket
        let target = activeVoiceTargetID
        let protocolVersion = serverProtocolVersion
        let voiceRouter = voiceRouter
        let reportFailure: @MainActor @Sendable (String) -> Void = { [weak self] message in
            self?.handleTransmitFailure(message)
        }
        transmitEncodingQueue.enqueue(
            samples: samples,
            configuration: configuration,
            framesPerPacket: framesPerPacket
        ) { result in
            switch result {
            case .buffered:
                break
            case .frame(let encoded):
                do {
                    let packet = try MumbleVoicePacket.clientAudioPacket(
                        opusData: encoded.opusData,
                        frameNumber: encoded.frameNumber,
                        target: target,
                        protocolVersion: protocolVersion
                    )
                    voiceRouter.enqueue(packet)
                } catch {
                    Task { await reportFailure(error.localizedDescription) }
                }
            case .failed(let error):
                Task { await reportFailure(String(describing: error)) }
            }
        }
    }

    func makeRealtimeVoiceEnqueuer() -> @Sendable ([Float]) -> Void {
        let configuration = opusEncoderConfiguration
        let framesPerPacket = opusFramesPerPacket
        let target = activeVoiceTargetID
        let protocolVersion = serverProtocolVersion
        let voiceRouter = voiceRouter
        let encodingQueue = transmitEncodingQueue
        return { samples in
            encodingQueue.enqueue(
                samples: samples,
                configuration: configuration,
                framesPerPacket: framesPerPacket
            ) { result in
                guard case .frame(let encoded) = result,
                      let packet = try? MumbleVoicePacket.clientAudioPacket(
                        opusData: encoded.opusData,
                        frameNumber: encoded.frameNumber,
                        target: target,
                        protocolVersion: protocolVersion
                      ) else { return }
                voiceRouter.enqueue(packet)
            }
        }
    }

    func makeRealtimeVoiceFinisher() -> @Sendable () -> Void {
        let encodingQueue = transmitEncodingQueue
        let target = activeVoiceTargetID
        let protocolVersion = serverProtocolVersion
        let voiceRouter = voiceRouter
        return {
            encodingQueue.finish { frameNumber in
                guard let frameNumber,
                      let packet = try? MumbleVoicePacket.clientAudioPacket(
                        opusData: Data(),
                        frameNumber: frameNumber,
                        target: target,
                        isTerminator: true,
                        protocolVersion: protocolVersion
                      ) else { return }
                voiceRouter.enqueue(packet)
            }
        }
    }

    func handleTransmitFailure(_ message: String) {
        audioErrorMessage = message
        finishTransmitPipeline()
    }

    func recordAudioPacketSent() {
        unpublishedAudioPacketsSent += 1
        if unpublishedAudioPacketsSent >= 10 {
            publishPendingAudioPacketCount()
        }
        guard audioPacketCountPublishTask == nil else { return }
        audioPacketCountPublishTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            publishPendingAudioPacketCount()
            audioPacketCountPublishTask = nil
        }
    }

    func publishPendingAudioPacketCount() {
        guard unpublishedAudioPacketsSent > 0 else { return }
        audioPacketsSent += unpublishedAudioPacketsSent
        unpublishedAudioPacketsSent = 0
    }

    /// Received-packet counting is batched so multi-speaker traffic (hundreds
    /// of packets per second) doesn't invalidate SwiftUI observation per packet.
    func recordAudioPacketReceived() {
        unpublishedAudioPacketsReceived += 1
        if unpublishedAudioPacketsReceived >= 25 {
            publishPendingReceivedAudioPacketCount()
        }
        guard receivedAudioPacketCountPublishTask == nil else { return }
        receivedAudioPacketCountPublishTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            publishPendingReceivedAudioPacketCount()
            receivedAudioPacketCountPublishTask = nil
        }
    }

    func publishPendingReceivedAudioPacketCount() {
        guard unpublishedAudioPacketsReceived > 0 else { return }
        audioPacketsReceived += unpublishedAudioPacketsReceived
        unpublishedAudioPacketsReceived = 0
    }

    func setTransmissionMode(_ mode: AudioTransmissionMode) {
        guard transmissionMode != mode else { return }
        stopAutomaticAudioCapture()
        endTransmission()
        transmissionMode = mode
        configureRealtimeVoiceActivity()
        UserDefaults.standard.set(mode.rawValue, forKey: "audioTransmissionMode")
        refreshAutomaticAudioCapture()
    }

    func cycleTransmissionMode() {
        let modes = AudioTransmissionMode.allCases
        let index = modes.firstIndex(of: transmissionMode) ?? 0
        setTransmissionMode(modes[(index + 1) % modes.count])
    }

    func setVoiceActivityThresholdDB(_ threshold: Double) {
        voiceActivityThresholdDB = min(-5, max(-70, threshold))
        configureRealtimeVoiceActivity()
        UserDefaults.standard.set(voiceActivityThresholdDB, forKey: "voiceActivityThresholdDB")
    }

    func configureRealtimeVoiceActivity() {
        realtimeVoiceActivity.configure(
            mode: transmissionMode == .continuous ? .continuous : .voiceActivity,
            thresholdDB: voiceActivityThresholdDB
        )
    }

    func setAudioSettingsVisible(_ visible: Bool) {
        isAudioSettingsVisible = visible
        if !visible { cancelAudioLoopbackTest() }
        refreshAutomaticAudioCapture()
    }

    func refreshAutomaticAudioCapture() {
        if shouldAutomaticallyMonitorMicrophone {
            startAutomaticAudioCapture()
        } else {
            stopAutomaticAudioCapture()
        }
    }

    var shouldAutomaticallyMonitorMicrophone: Bool {
        let connected: Bool
        if case .connected = connectionState { connected = true } else { connected = false }
        return !isMuted && transmissionMode != .pushToTalk && (connected || isAudioSettingsVisible)
    }

    func startAutomaticAudioCapture() {
        guard transmissionMode != .pushToTalk,
              !isMicrophoneMonitoring,
              automaticCaptureTask == nil else { return }
        automaticCaptureGeneration += 1
        let generation = automaticCaptureGeneration
        automaticCaptureTask = Task {
            defer {
                if generation == automaticCaptureGeneration {
                    automaticCaptureTask = nil
                }
            }
            let permissionGranted = await AudioCaptureService.requestMicrophonePermission()
            guard !Task.isCancelled,
                  generation == automaticCaptureGeneration,
                  shouldAutomaticallyMonitorMicrophone else { return }
            guard permissionGranted else {
                audioErrorMessage = L10n.text("audio.permissionDenied")
                return
            }
            do {
                voiceActivityGate.reset()
                realtimeVoiceActivity.reset()
                configureRealtimeVoiceActivity()
                audioCapture.selectDevice(selectedInputDeviceID)
                let frameStream = AsyncStream.makeStream(
                    of: [Float].self,
                    bufferingPolicy: .bufferingNewest(8)
                )
                automaticFrameContinuation = frameStream.continuation
                let frameContinuation = frameStream.continuation
                let processor = inputProcessor
                let voiceActivity = realtimeVoiceActivity
                let enqueueVoice = makeRealtimeVoiceEnqueuer()
                let finishVoice = makeRealtimeVoiceFinisher()
                let updateUI: @MainActor @Sendable (RealtimeVoiceDecision, UInt64) -> Void = { [weak self] decision, frameCount in
                    guard let self,
                          generation == self.automaticCaptureGeneration,
                          self.shouldAutomaticallyMonitorMicrophone else { return }
                    self.microphoneLevelFrameCounter = Int(frameCount)
                    self.microphoneLevelDB = decision.smoothedLevelDB
                    self.isVoiceActivityDetected = self.transmissionMode == .voiceActivity && decision.shouldSend
                    if let floor = decision.noiseFloorDB { self.noiseFloorDB = floor }
                }
                automaticFrameConsumerTask = Task.detached(priority: .high) {
                    var frameCount: UInt64 = 0
                    for await samples in frameStream.stream {
                        if Task.isCancelled { return }
                        frameCount &+= 1
                        let decision = voiceActivity.process(
                            levelDB: AudioLevelMeter.decibels(samples: samples)
                        )
                        if decision.didChange {
                            if !decision.shouldSend { finishVoice() }
                            DispatchQueue.main.async { [weak self] in
                                MainActor.assumeIsolated {
                                    self?.setTransmitting(decision.shouldSend)
                                }
                            }
                        }
                        if frameCount == 1 || frameCount.isMultiple(of: 10) || decision.didChange {
                            let displayedFrameCount = frameCount
                            DispatchQueue.main.async {
                                MainActor.assumeIsolated {
                                    updateUI(decision, displayedFrameCount)
                                    if displayedFrameCount == 1 || displayedFrameCount.isMultiple(of: 100) {
                                        AudioDiagnostics.shared.record(
                                            "ui.meter count=\(displayedFrameCount) db=\(decision.smoothedLevelDB)"
                                        )
                                    }
                                }
                            }
                        }
                        if decision.shouldSend {
                            if frameCount == 1 || frameCount.isMultiple(of: 100) {
                                AudioDiagnostics.shared.record("consumer.process.begin count=\(frameCount)")
                            }
                            let processed = await processor.processRealtime(samples)
                            if frameCount == 1 || frameCount.isMultiple(of: 100) {
                                AudioDiagnostics.shared.record("consumer.process.end count=\(frameCount)")
                            }
                            enqueueVoice(processed)
                        }
                    }
                }
                try audioCapture.start { samples in
                    frameContinuation.yield(samples)
                }
                audioPlayback?.undoSystemVoiceDucking()
                isMicrophoneMonitoring = true
            } catch {
                automaticFrameContinuation?.finish()
                automaticFrameContinuation = nil
                automaticFrameConsumerTask?.cancel()
                automaticFrameConsumerTask = nil
                audioErrorMessage = error.localizedDescription
            }
        }
    }

    func stopAutomaticAudioCapture() {
        automaticCaptureGeneration += 1
        automaticCaptureTask?.cancel()
        automaticCaptureTask = nil
        if isMicrophoneMonitoring { audioCapture.stop() }
        automaticFrameContinuation?.finish()
        automaticFrameContinuation = nil
        automaticFrameConsumerTask?.cancel()
        automaticFrameConsumerTask = nil
        isMicrophoneMonitoring = false
        microphoneLevelDB = -80
        microphoneLevelFrameCounter = 0
        lastDiagnosticSendDecision = false
        isVoiceActivityDetected = false
        voiceActivityGate.reset()
        levelSmoother.reset()
        finishTransmitPipeline()
    }

    func evaluateAutomaticCapturedLevel(_ levelDB: Double) -> Bool {
        guard transmissionMode != .pushToTalk else { return false }
        let smoothedLevel = levelSmoother.process(levelDB: levelDB)
        microphoneLevelFrameCounter += 1
        if microphoneLevelFrameCounter.isMultiple(of: 3) {
            microphoneLevelDB = smoothedLevel
        }
        if microphoneLevelFrameCounter == 1 || microphoneLevelFrameCounter.isMultiple(of: 100) {
            AudioDiagnostics.shared.record(
                "consumer.level frames=\(microphoneLevelFrameCounter) db=\(smoothedLevel) connected=\(connectionState)"
            )
        }
        let shouldSend: Bool
        switch transmissionMode {
        case .pushToTalk:
            shouldSend = false
        case .voiceActivity:
            shouldSend = voiceActivityGate.process(
                levelDB: smoothedLevel,
                thresholdDB: voiceActivityThresholdDB
            )
        case .continuous:
            shouldSend = true
        }
        isVoiceActivityDetected = transmissionMode == .voiceActivity && shouldSend
        if shouldSend != lastDiagnosticSendDecision {
            lastDiagnosticSendDecision = shouldSend
            AudioDiagnostics.shared.record(
                "vad.transition sending=\(shouldSend) db=\(smoothedLevel) threshold=\(voiceActivityThresholdDB)"
            )
        }
        // Learn the ambient noise floor only from frames the gate treats as
        // silence, so speech does not pull the estimate up.
        if transmissionMode == .voiceActivity, !shouldSend {
            noiseFloorDB = noiseFloorTracker.observeSilence(levelDB: smoothedLevel)
        }

        guard case .connected = connectionState, !isMuted else {
            finishTransmitPipeline()
            return false
        }
        if !shouldSend { finishTransmitPipeline() }
        return shouldSend
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        if muted { endTransmission() }
        isMuted = muted
        let connected: Bool
        if case .connected = connectionState { connected = true } else { connected = false }
        realtimeVoiceActivity.setTransmissionAllowed(connected && !muted)
        if audioCuesEnabled { playAudioCue(muted ? .muted : .unmuted) }
        // Unmuting while deafened makes no sense; drop deafen too.
        if !muted, isDeafened {
            isDeafened = false
            audioPlayback?.setMuted(false)
        }
        refreshAutomaticAudioCapture()
        syncSelfAudioState()
    }

    func toggleDeafen() {
        setDeafened(!isDeafened)
    }

    func setDeafened(_ deafened: Bool) {
        guard deafened != isDeafened else { return }
        isDeafened = deafened
        audioPlayback?.setMuted(deafened)
        if deafened {
            // Deafen implies mute, matching official behavior.
            if !isMuted { endTransmission() }
            isMuted = true
        } else if unmuteOnUndeafen {
            isMuted = false
        }
        refreshAutomaticAudioCapture()
        syncSelfAudioState()
    }

    /// Reconciles local mute/deafen with a server-driven change to our own user
    /// (e.g. an admin server-mute, or a change made by another session sharing
    /// this identity). Does not re-send, to avoid a feedback loop with our own
    /// echoed UserState.
    ///
    /// Not called on (re)synchronize: a freshly established session always
    /// reports `selfMute=false`/`selfDeaf=false`, which would otherwise clobber
    /// the mute/deafen the user set before a network drop. On sync the local
    /// state is authoritative and is pushed to the server via
    /// `reportSelfAudioState` instead.
    func applyServerSelfState(_ user: MumbleUser) {
        if user.isSelfMuted != isMuted {
            if user.isSelfMuted { endTransmission() }
            isMuted = user.isSelfMuted
            refreshAutomaticAudioCapture()
        }
        if user.isSelfDeafened != isDeafened {
            isDeafened = user.isSelfDeafened
            audioPlayback?.setMuted(isDeafened)
        }
    }

    /// Pushes the current self-mute/deafen state to the server when connected.
    func syncSelfAudioState() {
        guard case .connected(let session) = connectionState else { return }
        reportSelfAudioState(session: session)
    }

    func reportSelfAudioState(session: UInt32) {
        let muted = isMuted
        let deafened = isDeafened
        Task {
            if let frame = try? MumbleCommands.selfAudioState(
                session: session,
                selfMute: muted,
                selfDeaf: deafened
            ) {
                try? await controlConnection.send(frame)
            }
        }
    }

    func setAutoReconnectEnabled(_ enabled: Bool) {
        connectionCoordinator.setAutoReconnectEnabled(enabled)
    }

    func setUnmuteOnUndeafen(_ enabled: Bool) {
        unmuteOnUndeafen = enabled
        UserDefaults.standard.set(enabled, forKey: "unmuteOnUndeafen")
    }

    func scheduleReconnectIfNeeded() {
        guard autoReconnectEnabled,
              !suppressReconnect,
              reconnectTask == nil,
              let serverID = reconnectServerID,
              activeServerID == serverID,
              let delay = reconnectPolicy.nextDelay() else {
            isReconnecting = false
            return
        }

        isReconnecting = true
        reconnectAttempt = reconnectPolicy.attempt
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled,
                  autoReconnectEnabled,
                  !suppressReconnect,
                  activeServerID == serverID else {
                reconnectTask = nil
                isReconnecting = false
                return
            }
            reconnectTask = nil
            connect(password: pendingConnectionPassword, isReconnect: true)
        }
    }

    func userVolume(_ user: MumbleUser) -> Float {
        if let live = userVolumeGains[user.id] { return live }
        if let hash = user.certificateHash, let stored = persistedUserVolumes[hash] { return stored }
        return 1
    }

    func setUserVolume(_ volume: Float, for user: MumbleUser) {
        let clamped = min(3, max(0, volume))
        userVolumeGains[user.id] = clamped
        audioMixer.setGain(clamped, source: user.id)
        if let hash = user.certificateHash {
            if clamped == 1 {
                persistedUserVolumes.removeValue(forKey: hash)
            } else {
                persistedUserVolumes[hash] = clamped
            }
            persistUserVolumes()
        }
    }

    func isLocallyMuted(_ user: MumbleUser) -> Bool {
        if locallyMutedSessions.contains(user.id) { return true }
        if let hash = user.certificateHash { return persistedMutedUsers.contains(hash) }
        return false
    }

    func setLocallyMuted(_ muted: Bool, for user: MumbleUser) {
        if muted {
            locallyMutedSessions.insert(user.id)
        } else {
            locallyMutedSessions.remove(user.id)
        }
        audioMixer.setMuted(muted, source: user.id)
        if let hash = user.certificateHash {
            if muted {
                persistedMutedUsers.insert(hash)
            } else {
                persistedMutedUsers.remove(hash)
            }
            UserDefaults.standard.set(Array(persistedMutedUsers), forKey: "locallyMutedUsers")
        }
    }

    func toggleLocalMute(_ user: MumbleUser) {
        setLocallyMuted(!isLocallyMuted(user), for: user)
    }

    func persistUserVolumes() {
        if let data = try? JSONEncoder().encode(persistedUserVolumes) {
            UserDefaults.standard.set(data, forKey: "userVolumeGains")
        }
    }

    /// Applies any live or persisted volume/mute preference for a speaker to the
    /// mixer as soon as their audio source is registered.
    func seedMixerSettings(session: UInt32) {
        let user = findUser(session: session, in: channels)
        let hash = user?.certificateHash

        let gain = userVolumeGains[session]
            ?? hash.flatMap { persistedUserVolumes[$0] }
            ?? 1
        if gain != 1 {
            userVolumeGains[session] = gain
            audioMixer.setGain(gain, source: session)
        }

        let muted = locallyMutedSessions.contains(session)
            || (hash.map { persistedMutedUsers.contains($0) } ?? false)
        if muted {
            locallyMutedSessions.insert(session)
            audioMixer.setMuted(true, source: session)
        }
    }

    func autoCalibrateVoiceThreshold() {
        setVoiceActivityThresholdDB(noiseFloorTracker.recommendedThresholdDB)
    }
}
