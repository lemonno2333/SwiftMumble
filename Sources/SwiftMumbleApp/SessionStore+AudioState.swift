import Foundation
import MumbleAudio
import MumbleProtocol

extension SessionStore {
    var isMuted: Bool { get { audioSession.isMuted } set { audioSession.isMuted = newValue } }
    var isDeafened: Bool { get { audioSession.isDeafened } set { audioSession.isDeafened = newValue } }
    var isTransmitting: Bool { get { audioSession.isTransmitting } set { audioSession.isTransmitting = newValue } }
    var audioErrorMessage: String? { get { audioSession.errorMessage } set { audioSession.errorMessage = newValue } }
    var selectedInputDeviceID: UInt32? { get { audioSession.selectedInputDeviceID } set { audioSession.selectedInputDeviceID = newValue } }
    var selectedOutputDeviceID: UInt32? { get { audioSession.selectedOutputDeviceID } set { audioSession.selectedOutputDeviceID = newValue } }
    var audioPacketsSent: UInt64 { get { audioSession.packetsSent } set { audioSession.packetsSent = newValue } }
    var audioPacketsReceived: UInt64 { get { audioSession.packetsReceived } set { audioSession.packetsReceived = newValue } }
    var isShowingAudioWizard: Bool { get { audioSession.isShowingWizard } set { audioSession.isShowingWizard = newValue } }
    var transmissionMode: AudioTransmissionMode { get { audioSession.transmissionMode } set { audioSession.transmissionMode = newValue } }
    var voiceActivityThresholdDB: Double { get { audioSession.voiceActivityThresholdDB } set { audioSession.voiceActivityThresholdDB = newValue } }
    var microphoneLevelDB: Double { get { audioSession.microphoneLevelDB } set { audioSession.microphoneLevelDB = newValue } }
    var isVoiceActivityDetected: Bool { get { audioSession.isVoiceActivityDetected } set { audioSession.isVoiceActivityDetected = newValue } }
    var isMicrophoneMonitoring: Bool { get { audioSession.isMicrophoneMonitoring } set { audioSession.isMicrophoneMonitoring = newValue } }
    var userVolumeGains: [UInt32: Float] { get { audioSession.userVolumeGains } set { audioSession.userVolumeGains = newValue } }
    var locallyMutedSessions: Set<UInt32> { get { audioSession.locallyMutedSessions } set { audioSession.locallyMutedSessions = newValue } }
    var noiseFloorDB: Double { get { audioSession.noiseFloorDB } set { audioSession.noiseFloorDB = newValue } }
    var unmuteOnUndeafen: Bool { get { audioSession.unmuteOnUndeafen } set { audioSession.unmuteOnUndeafen = newValue } }
    var masterOutputVolume: Float { get { audioSession.masterOutputVolume } set { audioSession.masterOutputVolume = newValue } }
    var duckingEnabled: Bool { get { audioSession.duckingEnabled } set { audioSession.duckingEnabled = newValue } }
    var duckingVolume: Float { get { audioSession.duckingVolume } set { audioSession.duckingVolume = newValue } }
    var noiseSuppressionEnabled: Bool { get { audioSession.noiseSuppressionEnabled } set { audioSession.noiseSuppressionEnabled = newValue } }
    var pushToTalkHoldMilliseconds: Int { get { audioSession.pushToTalkHoldMilliseconds } set { audioSession.pushToTalkHoldMilliseconds = newValue } }
    var jitterBufferDelayFrames: Int { get { audioSession.jitterBufferDelayFrames } set { audioSession.jitterBufferDelayFrames = newValue } }
    var opusBitrateKbps: Int { get { audioSession.opusBitrateKbps } set { audioSession.opusBitrateKbps = newValue } }
    var opusComplexity: Int { get { audioSession.opusComplexity } set { audioSession.opusComplexity = newValue } }
    var opusExpectedPacketLossPercent: Int { get { audioSession.opusExpectedPacketLossPercent } set { audioSession.opusExpectedPacketLossPercent = newValue } }
    var opusInbandFECEnabled: Bool { get { audioSession.opusInbandFECEnabled } set { audioSession.opusInbandFECEnabled = newValue } }
    var opusLowLatencyEnabled: Bool { get { audioSession.opusLowLatencyEnabled } set { audioSession.opusLowLatencyEnabled = newValue } }
    var opusFramesPerPacket: Int { get { audioSession.opusFramesPerPacket } set { audioSession.opusFramesPerPacket = newValue } }
    var automaticGainControlEnabled: Bool { get { audioSession.automaticGainControlEnabled } set { audioSession.automaticGainControlEnabled = newValue } }
    var echoCancellationEnabled: Bool { get { audioSession.echoCancellationEnabled } set { audioSession.echoCancellationEnabled = newValue } }
    var audioCuesEnabled: Bool { get { audioSession.audioCuesEnabled } set { audioSession.audioCuesEnabled = newValue } }
    var voiceProcessingEnabled: Bool { audioSession.voiceProcessingEnabled }
    var audioLoopbackTestPhase: AudioLoopbackTestPhase { get { audioSession.loopbackTestPhase } set { audioSession.loopbackTestPhase = newValue } }

    var talkingTracker: TalkingStateTracker { get { audioSession.talkingTracker } set { audioSession.talkingTracker = newValue } }
    var talkingPruneTask: Task<Void, Never>? { get { audioSession.talkingPruneTask } set { audioSession.talkingPruneTask = newValue } }
    var audioCapture: AudioCaptureBackend { audioSession.capture }
    var inputProcessor: AudioInputProcessor { audioSession.inputProcessor }
    var realtimeVoiceActivity: RealtimeVoiceActivityProcessor { audioSession.realtimeVoiceActivity }
    var audioCueService: AudioCueService { audioSession.cueService }
    var transmitEncodingQueue: AudioTransmitEncodingQueue { audioSession.transmitEncodingQueue }
    var audioPlayback: AudioPlaybackBackend? { get { audioSession.playback } set { audioSession.playback = newValue } }
    var audioMixer: AudioFrameMixer { audioSession.mixer }
    var audioIngress: AudioReceiveIngress { audioSession.ingress }
    var voiceActivityGate: VoiceActivityGate { get { audioSession.voiceActivityGate } set { audioSession.voiceActivityGate = newValue } }
    var levelSmoother: LevelSmoother { get { audioSession.levelSmoother } set { audioSession.levelSmoother = newValue } }
    var noiseFloorTracker: NoiseFloorTracker { get { audioSession.noiseFloorTracker } set { audioSession.noiseFloorTracker = newValue } }
    var persistedUserVolumes: [String: Float] { get { audioSession.persistedUserVolumes } set { audioSession.persistedUserVolumes = newValue } }
    var persistedMutedUsers: Set<String> { get { audioSession.persistedMutedUsers } set { audioSession.persistedMutedUsers = newValue } }
    var manualCaptureTask: Task<Void, Never>? { get { audioSession.manualCaptureTask } set { audioSession.manualCaptureTask = newValue } }
    var manualFrameConsumerTask: Task<Void, Never>? { get { audioSession.manualFrameConsumerTask } set { audioSession.manualFrameConsumerTask = newValue } }
    var manualFrameContinuation: AsyncStream<[Float]>.Continuation? { get { audioSession.manualFrameContinuation } set { audioSession.manualFrameContinuation = newValue } }
    var manualCaptureGeneration: Int { get { audioSession.manualCaptureGeneration } set { audioSession.manualCaptureGeneration = newValue } }
    var pushToTalkReleaseTask: Task<Void, Never>? { get { audioSession.pushToTalkReleaseTask } set { audioSession.pushToTalkReleaseTask = newValue } }
    var audioLoopbackTestTask: Task<Void, Never>? { get { audioSession.loopbackTestTask } set { audioSession.loopbackTestTask = newValue } }
    var audioLoopbackFrames: [[Float]] { get { audioSession.loopbackFrames } set { audioSession.loopbackFrames = newValue } }
    var automaticCaptureTask: Task<Void, Never>? { get { audioSession.automaticCaptureTask } set { audioSession.automaticCaptureTask = newValue } }
    var automaticFrameConsumerTask: Task<Void, Never>? { get { audioSession.automaticFrameConsumerTask } set { audioSession.automaticFrameConsumerTask = newValue } }
    var automaticFrameContinuation: AsyncStream<[Float]>.Continuation? { get { audioSession.automaticFrameContinuation } set { audioSession.automaticFrameContinuation = newValue } }
    var automaticCaptureGeneration: Int { get { audioSession.automaticCaptureGeneration } set { audioSession.automaticCaptureGeneration = newValue } }
    var isAudioSettingsVisible: Bool { get { audioSession.isSettingsVisible } set { audioSession.isSettingsVisible = newValue } }
    var microphoneLevelFrameCounter: Int { get { audioSession.microphoneLevelFrameCounter } set { audioSession.microphoneLevelFrameCounter = newValue } }
    var lastDiagnosticSendDecision: Bool { get { audioSession.lastDiagnosticSendDecision } set { audioSession.lastDiagnosticSendDecision = newValue } }
    var unpublishedAudioPacketsSent: UInt64 { get { audioSession.unpublishedPacketsSent } set { audioSession.unpublishedPacketsSent = newValue } }
    var audioPacketCountPublishTask: Task<Void, Never>? { get { audioSession.packetCountPublishTask } set { audioSession.packetCountPublishTask = newValue } }
    var unpublishedAudioPacketsReceived: UInt64 { get { audioSession.unpublishedPacketsReceived } set { audioSession.unpublishedPacketsReceived = newValue } }
    var receivedAudioPacketCountPublishTask: Task<Void, Never>? { get { audioSession.receivedPacketCountPublishTask } set { audioSession.receivedPacketCountPublishTask = newValue } }
    var droppedSelfAudioPackets: UInt64 { get { audioSession.droppedSelfPackets } set { audioSession.droppedSelfPackets = newValue } }
}
