import AppKit
import Foundation
import MumbleAudio
import MumbleProtocol
import MumbleSystem
extension SessionStore {
    var connectionLabel: String {
        if isReconnecting {
            return L10n.text("connection.reconnecting", reconnectAttempt)
        }
        switch connectionState {
        case .disconnected: return L10n.text("connection.disconnected")
        case .connecting: return L10n.text("connection.connecting")
        case .authenticating: return L10n.text("connection.authenticating")
        case .connected: return L10n.text("connection.connected")
        case .failed: return L10n.text("connection.failed")
        }
    }

    var connectionDetail: String {
        switch connectionState {
        case .failed(let message): message
        case .disconnected: L10n.text("connection.disconnected.help")
        case .connecting: L10n.text("connection.connecting.help")
        case .authenticating: L10n.text("connection.authenticating.help")
        case .connected: L10n.text("connection.connected.help")
        }
    }

    var transportLabel: String {
        if isReconnecting { return connectionLabel }
        guard case .connected = connectionState else { return connectionLabel }
        return isUsingUDP ? L10n.text("connection.udp") : L10n.text("connection.tcp")
    }

    var activeReceivePipelineCount: Int { audioIngress.pipelineCount }
    var averageReceiveJitterMilliseconds: Double {
        audioIngress.averageJitterMilliseconds
    }
    var averageReceiveBufferMilliseconds: Int {
        audioIngress.averageBufferMilliseconds ?? jitterBufferDelayFrames * 10
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        if !enabled {
            notificationsEnabled = false
            UserDefaults.standard.set(false, forKey: "notificationsEnabled")
            return
        }
        Task {
            let granted = await MumbleNotificationService.requestAuthorization()
            notificationsEnabled = granted
            UserDefaults.standard.set(granted, forKey: "notificationsEnabled")
            if !granted {
                serverManagementError = L10n.text("notifications.permissionDenied")
            }
        }
    }

    func setTouchBarControlStripEnabled(_ enabled: Bool) {
        touchBarControlStripEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "touchBarControlStripEnabled")
        NotificationCenter.default.post(name: .touchBarControlStripPreferenceChanged, object: nil)
    }

    func setMasterOutputVolume(_ volume: Float) {
        masterOutputVolume = min(2, max(0, volume))
        audioMixer.setMasterGain(masterOutputVolume)
        UserDefaults.standard.set(masterOutputVolume, forKey: "masterOutputVolume")
    }

    func setDuckingEnabled(_ enabled: Bool) {
        duckingEnabled = enabled
        audioMixer.setDuckingActive(enabled && isTransmitting)
        UserDefaults.standard.set(enabled, forKey: "duckingEnabled")
    }

    func setDuckingVolume(_ volume: Float) {
        duckingVolume = min(1, max(0, volume))
        audioMixer.setDuckingGain(duckingVolume)
        UserDefaults.standard.set(duckingVolume, forKey: "duckingVolume")
    }

    func setNoiseSuppressionEnabled(_ enabled: Bool) {
        noiseSuppressionEnabled = enabled
        updateInputProcessorConfiguration()
        UserDefaults.standard.set(enabled, forKey: "noiseSuppressionEnabled")
    }

    func setPushToTalkHoldMilliseconds(_ milliseconds: Int) {
        pushToTalkHoldMilliseconds = PushToTalkHoldConfiguration(milliseconds: milliseconds).milliseconds
        UserDefaults.standard.set(pushToTalkHoldMilliseconds, forKey: "pushToTalkHoldMilliseconds")
    }

    func setJitterBufferDelayFrames(_ frames: Int) {
        jitterBufferDelayFrames = min(10, max(1, frames))
        UserDefaults.standard.set(jitterBufferDelayFrames, forKey: "jitterBufferDelayFrames")
    }

    func setTextToSpeechEnabled(_ enabled: Bool) {
        textToSpeechEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "textToSpeechEnabled")
        if !enabled { messageSpeechService.stop() }
    }

    func setOpusBitrateKbps(_ value: Int) {
        opusBitrateKbps = min(128, max(12, value))
        UserDefaults.standard.set(opusBitrateKbps, forKey: "opusBitrateKbps")
    }

    func setOpusComplexity(_ value: Int) {
        opusComplexity = min(10, max(0, value))
        UserDefaults.standard.set(opusComplexity, forKey: "opusComplexity")
    }

    func setOpusExpectedPacketLossPercent(_ value: Int) {
        opusExpectedPacketLossPercent = min(30, max(0, value))
        UserDefaults.standard.set(opusExpectedPacketLossPercent, forKey: "opusExpectedPacketLossPercent")
    }

    func setOpusInbandFECEnabled(_ enabled: Bool) {
        opusInbandFECEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "opusInbandFECEnabled")
    }

    func setOpusLowLatencyEnabled(_ enabled: Bool) {
        opusLowLatencyEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "opusLowLatencyEnabled")
    }

    func setOpusFramesPerPacket(_ value: Int) {
        opusFramesPerPacket = [1, 2, 4, 6].contains(value) ? value : 2
        UserDefaults.standard.set(opusFramesPerPacket, forKey: "opusFramesPerPacket")
    }

    func setAutomaticGainControlEnabled(_ enabled: Bool) {
        automaticGainControlEnabled = enabled
        updateInputProcessorConfiguration()
        UserDefaults.standard.set(enabled, forKey: "automaticGainControlEnabled")
    }
    func setEchoCancellationEnabled(_ enabled: Bool) {
        echoCancellationEnabled = enabled
        inputProcessor.resetEchoCancellation()
        updateInputProcessorConfiguration()
        UserDefaults.standard.set(enabled, forKey: "echoCancellationEnabled")
    }

    func updateInputProcessorConfiguration() {
        inputProcessor.configure(
            echo: echoCancellationEnabled,
            noiseSuppression: noiseSuppressionEnabled,
            automaticGain: automaticGainControlEnabled
        )
    }

    func setAudioCuesEnabled(_ enabled: Bool) {
        audioCuesEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "audioCuesEnabled")
    }

    /// Persists the voice-processing preference. It takes effect on the next
    /// launch: the shared audio unit is chosen when `AudioSessionController` is
    /// built, and swapping the capture/playback backend on a live connection
    /// would tear down active audio.
    func setVoiceProcessingEnabled(_ enabled: Bool) {
        guard enabled != voiceProcessingEnabled else { return }
        UserDefaults.standard.set(enabled, forKey: "voiceProcessingEnabled")
        audioErrorMessage = L10n.text("settings.voiceProcessing.restartRequired")
    }

    var opusEncoderConfiguration: OpusEncoderConfiguration {
        OpusEncoderConfiguration(
            bitrate: Int32(opusBitrateKbps * 1_000),
            complexity: Int32(opusComplexity),
            expectedPacketLossPercent: Int32(opusExpectedPacketLossPercent),
            inbandFEC: opusInbandFECEnabled,
            lowLatency: opusLowLatencyEnabled
        )
    }

    func startAudioLoopbackTest() {
        guard audioLoopbackTestPhase == .idle,
              !isTransmitting,
              !isMicrophoneMonitoring else { return }
        audioLoopbackTestTask = Task {
            let granted = await AudioCaptureService.requestMicrophonePermission()
            guard granted, !Task.isCancelled else {
                if !granted { audioErrorMessage = L10n.text("audio.permissionDenied") }
                audioLoopbackTestTask = nil
                return
            }
            do {
                audioLoopbackFrames = []
                audioLoopbackTestPhase = .recording
                audioCapture.selectDevice(selectedInputDeviceID)
                try audioCapture.start { [weak self] samples in
                    Task { @MainActor in self?.audioLoopbackFrames.append(samples) }
                }
                try await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                audioCapture.stop()
                audioLoopbackTestPhase = .playing
                let playback = try AudioPlaybackService()
                try playback.selectDevice(selectedOutputDeviceID)
                try playback.start()
                for frame in audioLoopbackFrames { try playback.enqueue(samples: frame) }
                try await Task.sleep(for: .milliseconds(max(300, audioLoopbackFrames.count * 10 + 200)))
                playback.stop()
                audioLoopbackFrames = []
                audioLoopbackTestPhase = .idle
                audioLoopbackTestTask = nil
            } catch is CancellationError {
                audioCapture.stop()
                audioLoopbackFrames = []
                audioLoopbackTestPhase = .idle
                audioLoopbackTestTask = nil
            } catch {
                audioCapture.stop()
                audioLoopbackFrames = []
                audioLoopbackTestPhase = .idle
                audioLoopbackTestTask = nil
                audioErrorMessage = error.localizedDescription
            }
        }
    }

    func cancelAudioLoopbackTest() {
        guard audioLoopbackTestTask != nil || audioLoopbackTestPhase != .idle else { return }
        audioLoopbackTestTask?.cancel()
        audioLoopbackTestTask = nil
        audioCapture.stop()
        audioLoopbackFrames = []
        audioLoopbackTestPhase = .idle
    }

    func setTransmitting(_ transmitting: Bool) {
        let changed = transmitting != isTransmitting
        isTransmitting = transmitting
        if changed {
            AudioDiagnostics.shared.record(
                "transmit.state active=\(transmitting) duckingEnabled=\(duckingEnabled) duckingVolume=\(duckingVolume)"
            )
        }
        audioMixer.setDuckingActive(duckingEnabled && transmitting)
        // Reflect our own talk state in the live speaking set (own row lights
        // up while transmitting). Deferred so this stays off the realtime
        // transmit transition.
        if changed {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.publishTalkingSessions()
            }
        }
    }

    func ensureAudioPlayback() throws -> AudioPlaybackBackend {
        if let audioPlayback {
            try audioPlayback.start()
            return audioPlayback
        }
        let playback = try audioSession.makePlayback()
        try playback.selectDevice(selectedOutputDeviceID)
        playback.setMuted(isDeafened)
        try playback.start()
        audioPlayback = playback
        return playback
    }

    func playAudioCue(_ cue: AudioCueService.Cue) {
        do {
            let playback = try ensureAudioPlayback()
            playback.enqueueOverlay(samples: audioCueService.samples(for: cue))
        } catch {
            audioErrorMessage = error.localizedDescription
        }
    }
}
