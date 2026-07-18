import Foundation
import MumbleAudio
import MumbleProtocol
import Observation

@MainActor
@Observable
final class AudioSessionController {
    var isMuted = false
    var isDeafened = false
    var isTransmitting = false
    var errorMessage: String?
    var selectedInputDeviceID: UInt32?
    var selectedOutputDeviceID: UInt32?
    var packetsSent: UInt64 = 0
    var packetsReceived: UInt64 = 0
    var isShowingWizard = false
    var transmissionMode: AudioTransmissionMode = .pushToTalk
    var voiceActivityThresholdDB = -35.0
    var microphoneLevelDB = -80.0
    var isVoiceActivityDetected = false
    var isMicrophoneMonitoring = false
    var userVolumeGains: [UInt32: Float] = [:]
    var locallyMutedSessions: Set<UInt32> = []
    var noiseFloorDB = -60.0
    var unmuteOnUndeafen = true
    var masterOutputVolume: Float = 1
    var duckingEnabled = false
    var duckingVolume: Float = 0.35
    var noiseSuppressionEnabled = false
    var pushToTalkHoldMilliseconds = 0
    var jitterBufferDelayFrames = 3
    var opusBitrateKbps = 40
    var opusComplexity = 8
    var opusExpectedPacketLossPercent = 5
    var opusInbandFECEnabled = true
    var opusLowLatencyEnabled = false
    var opusFramesPerPacket = 2
    var automaticGainControlEnabled = false
    var echoCancellationEnabled = false
    var audioCuesEnabled = false
    var loopbackTestPhase: AudioLoopbackTestPhase = .idle
    /// Route capture + playback through one VoiceProcessingIO unit (system AEC).
    /// Opt-in; the app defaults to the two independent AUHAL services.
    var voiceProcessingEnabled = false

    @ObservationIgnored var talkingTracker = TalkingStateTracker()
    @ObservationIgnored var talkingPruneTask: Task<Void, Never>?
    @ObservationIgnored let voiceProcessingBackend: VoiceProcessingBackend?
    @ObservationIgnored let capture: AudioCaptureBackend
    @ObservationIgnored let inputProcessor = AudioInputProcessor()
    @ObservationIgnored let realtimeVoiceActivity = RealtimeVoiceActivityProcessor()
    @ObservationIgnored let cueService = AudioCueService()
    @ObservationIgnored let transmitEncodingQueue = AudioTransmitEncodingQueue()
    @ObservationIgnored var playback: AudioPlaybackBackend?
    @ObservationIgnored let mixer = AudioFrameMixer()
    @ObservationIgnored lazy var ingress = AudioReceiveIngress(mixer: mixer)
    @ObservationIgnored var voiceActivityGate = VoiceActivityGate()
    @ObservationIgnored var levelSmoother = LevelSmoother()
    @ObservationIgnored var noiseFloorTracker = NoiseFloorTracker()
    @ObservationIgnored var persistedUserVolumes: [String: Float] = [:]
    @ObservationIgnored var persistedMutedUsers: Set<String> = []
    @ObservationIgnored var manualCaptureTask: Task<Void, Never>?
    @ObservationIgnored var manualFrameConsumerTask: Task<Void, Never>?
    @ObservationIgnored var manualFrameContinuation: AsyncStream<[Float]>.Continuation?
    @ObservationIgnored var manualCaptureGeneration = 0
    @ObservationIgnored var pushToTalkReleaseTask: Task<Void, Never>?
    @ObservationIgnored var loopbackTestTask: Task<Void, Never>?
    @ObservationIgnored var loopbackFrames: [[Float]] = []
    @ObservationIgnored var automaticCaptureTask: Task<Void, Never>?
    @ObservationIgnored var automaticFrameConsumerTask: Task<Void, Never>?
    @ObservationIgnored var automaticFrameContinuation: AsyncStream<[Float]>.Continuation?
    @ObservationIgnored var automaticCaptureGeneration = 0
    @ObservationIgnored var isSettingsVisible = false
    @ObservationIgnored var microphoneLevelFrameCounter = 0
    @ObservationIgnored var lastDiagnosticSendDecision = false
    @ObservationIgnored var unpublishedPacketsSent: UInt64 = 0
    @ObservationIgnored var packetCountPublishTask: Task<Void, Never>?
    @ObservationIgnored var unpublishedPacketsReceived: UInt64 = 0
    @ObservationIgnored var receivedPacketCountPublishTask: Task<Void, Never>?
    @ObservationIgnored var droppedSelfPackets: UInt64 = 0

    init(voiceProcessingEnabled: Bool = false) {
        self.voiceProcessingEnabled = voiceProcessingEnabled
        if voiceProcessingEnabled {
            let backend = VoiceProcessingBackend()
            voiceProcessingBackend = backend
            capture = backend.capture
        } else {
            voiceProcessingBackend = nil
            capture = AudioCaptureService()
        }
    }

    /// Builds the playback backend matching the active capture backend. The
    /// VPIO path shares one unit for capture and playback; the default path
    /// creates an independent AUHAL output service.
    func makePlayback() throws -> AudioPlaybackBackend {
        if let voiceProcessingBackend { return voiceProcessingBackend.playback }
        return try AudioPlaybackService()
    }
}
