import Foundation
import AppKit
import MumbleAudio
import MumbleProtocol
import MumbleSystem
import Observation
import OSLog

private let identityLogger = Logger(subsystem: "com.leo.SwiftMumble", category: "ClientIdentity")

struct ChatEntry: Identifiable, Equatable {
    let id = UUID()
    var author: String
    var timestamp: Date
    var text: String
    var isLocal: Bool
    var isPrivate: Bool = false
}

struct PendingServerCertificate: Identifiable, Equatable {
    let id = UUID()
    var serverID: MumbleServer.ID
    var host: String
    var subject: String
    var fingerprint: MumbleCertificateFingerprint
}

enum AudioTransmissionMode: String, CaseIterable, Codable, Sendable {
    case pushToTalk
    case voiceActivity
    case continuous
}

enum AudioLoopbackTestPhase: Equatable {
    case idle
    case recording
    case playing
}

enum IdleAudioAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, mute, deafen
    var id: String { rawValue }
}
enum ChannelExpansionPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case currentPath, all, collapsed
    var id: String { rawValue }
}

enum ConfiguredVoiceTarget: Codable, Equatable, Sendable {
    case user(session: UInt32, name: String)
    case channel(id: UInt32, name: String, links: Bool, children: Bool)
}

@MainActor
@Observable
final class SessionStore {
    struct ServerContextAction: Identifiable, Equatable {
        var id: String { action }; var action: String; var title: String; var contexts: UInt32
    }
    var servers: [MumbleServer]
    var selectedServerID: MumbleServer.ID? {
        didSet {
            if selectedServerID != oldValue {
                loadChannelPreferences()
                applyShortcutConfigurationForSelectedServer()
            }
        }
    }
    var selectedChannelID: MumbleChannel.ID?
    var channels: [MumbleChannel]
    var connectionState: ConnectionState
    var isMuted = false
    var isDeafened = false
    var isShowingServerSheet = false
    var editingServerID: MumbleServer.ID?
    var pendingServerDeletion: MumbleServer?
    var serverManagementError: String?
    var chatDraft = ""
    var serverWelcomeText = ""
    var chatEntries: [ChatEntry] = []
    var isTransmitting = false
    var audioErrorMessage: String?
    var pendingServerCertificate: PendingServerCertificate?
    var isUsingUDP = false
    var selectedInputDeviceID: UInt32?
    var selectedOutputDeviceID: UInt32?
    var clientIdentityInfo: ClientIdentityInfo?
    var clientIdentityError: String?
    var serverRecognizedIdentityHash: String?
    var isGlobalPushToTalkEnabled = false
    var globalPushToTalkError: String?
    var globalPushToTalkShortcut: GlobalHotKeyShortcut = .default
    var pushToMuteShortcut = GlobalHotKeyShortcut(keyCode: 46, keyLabel: "M", option: true, control: true)
    var isPushToMuteEnabled = false
    var areGlobalAudioShortcutsEnabled = false
    var globalAudioShortcuts: [GlobalAudioShortcutAction: GlobalHotKeyShortcut] = [
        .toggleMute: GlobalHotKeyShortcut(keyCode: 46, keyLabel: "M", command: true, shift: true),
        .toggleDeafen: GlobalHotKeyShortcut(keyCode: 2, keyLabel: "D", command: true, shift: true),
        .volumeDown: GlobalHotKeyShortcut(keyCode: 27, keyLabel: "-", option: true, control: true),
        .volumeUp: GlobalHotKeyShortcut(keyCode: 24, keyLabel: "+", option: true, control: true),
        .cycleTransmissionMode: GlobalHotKeyShortcut(keyCode: 17, keyLabel: "T", option: true, control: true)
    ]
    var idleAudioAction: IdleAudioAction = .none
    var idleTimeoutMinutes = 10
    var configuredVoiceTarget: ConfiguredVoiceTarget?
    var whisperShortcut = GlobalHotKeyShortcut(keyCode: 13, keyLabel: "W", option: true, control: true)
    var isWhisperShortcutEnabled = false
    var serverShortcutOverrides: [String: ServerShortcutConfiguration] = [:]
    var friendCertificateHashes: Set<String> = []
    var localUserNicknames: [String: String] = [:]
    var ignoredMessageUserHashes: Set<String> = []
    var ignoredTTSUserHashes: Set<String> = []
    var doubleClickPTTTogglesContinuous = false
    var profileEditorTarget: MumbleUser?
    var moderationRequest: UserModerationRequest?
    var aclEditorChannel: MumbleChannel?
    var aclConfiguration: MumbleACLConfiguration?
    var isLoadingACL = false
    var isShowingRegisteredUsers = false
    var registeredUsers: [MumbleRegisteredUser] = []
    var isLoadingRegisteredUsers = false
    var audioPacketsSent: UInt64 = 0
    var audioPacketsReceived: UInt64 = 0
    var isShowingAudioWizard = false
    var publicServerDirectoryEnabled = false
    var publicServers: [PublicMumbleServer] = []
    var isLoadingPublicServers = false
    var publicServerError: String?
    var connectionTimeoutSeconds = 15
    var controlPingIntervalSeconds = 20
    var publicServerPingResults: [String: ServerPingResult] = [:]
    var isPingingPublicServers = false
    var proxyType: MumbleProxyType = .none
    var proxyHost = ""
    var proxyPort: UInt16 = 1080
    var proxyUsername = ""
    var serverContextActions: [ServerContextAction] = []
    var serverSuggestedPushToTalk: Bool?
    var serverSuggestedPositionalAudio: Bool?
    var serverSuggestedVersion: UInt64?
    var serverMessageLengthLimit = 5_000
    var serverImageMessageLengthLimit = 128_000
    var serverAllowsHTML = true
    var chatLogLimit = 500
    var chatUses24HourTime = false
    var isShowingServerInformation = false
    var lastControlPingMilliseconds: Double?
    var serverMaximumUsers: UInt32?
    var serverMaximumBandwidth: UInt32?
    var serverRecordingAllowed = false
    var channelExpansionPolicy: ChannelExpansionPolicy = .currentPath
    var showsReturnToPreviousChannelControl = false
    var showsHideEmptyChannelsControl = false
    var expandedChannelIDs: Set<UInt32> = []
    var isRecordingGlobalShortcut = false
    var transmissionMode: AudioTransmissionMode = .pushToTalk
    var voiceActivityThresholdDB = -35.0
    var microphoneLevelDB = -80.0
    var isVoiceActivityDetected = false
    var isMicrophoneMonitoring = false
    var userVolumeGains: [UInt32: Float] = [:]
    var locallyMutedSessions: Set<UInt32> = []
    var noiseFloorDB = -60.0
    var autoReconnectEnabled = true
    var unmuteOnUndeafen = true
    var isReconnecting = false
    var reconnectAttempt = 0
    var privateMessageTarget: MumbleUser?
    var userInformationTarget: MumbleUser?
    var userStatistics: MumbleUserStatistics?
    var isLoadingUserStatistics = false
    var notificationsEnabled = false
    var masterOutputVolume: Float = 1
    var duckingEnabled = false
    var duckingVolume: Float = 0.35
    var noiseSuppressionEnabled = false
    var pushToTalkHoldMilliseconds = 0
    var jitterBufferDelayFrames = 3
    var textToSpeechEnabled = false
    var opusBitrateKbps = 40
    var opusComplexity = 8
    var opusExpectedPacketLossPercent = 5
    var opusInbandFECEnabled = true
    var opusLowLatencyEnabled = false
    var opusFramesPerPacket = 2
    var automaticGainControlEnabled = false
    var echoCancellationEnabled = false
    var audioCuesEnabled = false
    var audioLoopbackTestPhase: AudioLoopbackTestPhase = .idle
    var channelEditorRequest: ChannelEditorRequest?
    var pendingChannelDeletion: MumbleChannel?
    var listeningChannelIDs: Set<UInt32> = []
    var listeningChannelVolumes: [UInt32: Float] = [:]
    var hideEmptyChannels = false
    var hiddenChannelIDs: Set<UInt32> = []
    var pinnedChannelIDs: Set<UInt32> = []
    var discoveredServers: [DiscoveredMumbleServer] = []

    @ObservationIgnored private let controlConnection: MumbleControlConnection
    @ObservationIgnored private let voiceRouter: MumbleVoiceRouter
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var protocolState = MumbleServerState()
    @ObservationIgnored private var channelSnapshot: [MumbleChannel] = []
    @ObservationIgnored private var talkingTracker = TalkingStateTracker()
    @ObservationIgnored private var talkingPruneTask: Task<Void, Never>?
    @ObservationIgnored private var channelHistory = MumbleChannelHistory()
    @ObservationIgnored private let audioCapture = AudioCaptureService()
    @ObservationIgnored private let noiseSuppressor = RNNoiseSuppressor()
    @ObservationIgnored private let automaticGainControl = AutomaticGainControl()
    @ObservationIgnored private let echoCanceller = AdaptiveEchoCanceller()
    @ObservationIgnored private let messageSpeechService = MessageSpeechService()
    @ObservationIgnored private let audioCueService = AudioCueService()
    @ObservationIgnored private let transmitEncodingQueue = AudioTransmitEncodingQueue()
    @ObservationIgnored private var audioPlayback: AudioPlaybackService?
    @ObservationIgnored private var audioReceivePipelines: [UInt32: AudioReceivePipeline] = [:]
    @ObservationIgnored private var audioDrainTasks: [UInt32: Task<Void, Never>] = [:]
    @ObservationIgnored private let audioMixer = AudioFrameMixer()
    @ObservationIgnored private var audioMixTask: Task<Void, Never>?
    @ObservationIgnored private var serverProtocolVersion = MumbleProtocolVersion(major: 1, minor: 4, patch: 0)
    @ObservationIgnored private var pendingConnectionPassword = ""
    @ObservationIgnored private var cryptState: MumbleCryptState?
    @ObservationIgnored private var udpConnection: MumbleUDPConnection?
    @ObservationIgnored private var udpTask: Task<Void, Never>?
    @ObservationIgnored private var udpPingTask: Task<Void, Never>?
    @ObservationIgnored private var lastUDPResponseAt: Date?
    @ObservationIgnored private var clientIdentity: MumbleTLSClientIdentity?
    @ObservationIgnored private var globalPushToTalkHotKey: GlobalPushToTalkHotKey?
    @ObservationIgnored private var pushToMuteHotKey: GlobalPushToTalkHotKey?
    @ObservationIgnored private var muteStateBeforePushToMute = false
    @ObservationIgnored private var globalAudioHotKeys: [GlobalAudioShortcutAction: GlobalPushToTalkHotKey] = [:]
    @ObservationIgnored private var idleMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var didPerformIdleAction = false
    @ObservationIgnored private var whisperHotKey: GlobalPushToTalkHotKey?
    @ObservationIgnored private var activeVoiceTargetID: UInt32 = 0
    @ObservationIgnored private var isWhisperPressed = false
    @ObservationIgnored private var requestedUserResourceSessions: Set<UInt32> = []
    @ObservationIgnored private var chatHistory: [String] = []
    @ObservationIgnored private var chatHistoryIndex: Int?
    @ObservationIgnored private var voiceActivityGate = VoiceActivityGate()
    @ObservationIgnored private var levelSmoother = LevelSmoother()
    @ObservationIgnored private var noiseFloorTracker = NoiseFloorTracker()
    @ObservationIgnored private var persistedUserVolumes: [String: Float] = [:]
    @ObservationIgnored private var persistedMutedUsers: Set<String> = []
    @ObservationIgnored private var manualCaptureTask: Task<Void, Never>?
    @ObservationIgnored private var manualFrameConsumerTask: Task<Void, Never>?
    @ObservationIgnored private var manualFrameContinuation: AsyncStream<[Float]>.Continuation?
    @ObservationIgnored private var manualCaptureGeneration = 0
    @ObservationIgnored private var pushToTalkReleaseTask: Task<Void, Never>?
    @ObservationIgnored private var audioLoopbackTestTask: Task<Void, Never>?
    @ObservationIgnored private var audioLoopbackFrames: [[Float]] = []
    @ObservationIgnored private var reconnectPolicy = MumbleReconnectPolicy()
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectServerID: MumbleServer.ID?
    @ObservationIgnored private var suppressReconnect = false
    @ObservationIgnored private var didSynchronize = false
    @ObservationIgnored private var automaticCaptureTask: Task<Void, Never>?
    @ObservationIgnored private var automaticFrameConsumerTask: Task<Void, Never>?
    @ObservationIgnored private var automaticFrameContinuation: AsyncStream<[Float]>.Continuation?
    @ObservationIgnored private var automaticCaptureGeneration = 0
    @ObservationIgnored private var isAudioSettingsVisible = false
    @ObservationIgnored private var microphoneLevelFrameCounter = 0
    @ObservationIgnored private var unpublishedAudioPacketsSent: UInt64 = 0
    @ObservationIgnored private var audioPacketCountPublishTask: Task<Void, Never>?
    @ObservationIgnored private var pendingChannelPath: [String] = []
    @ObservationIgnored private var requestedChannelDescriptions: Set<UInt32> = []
    @ObservationIgnored private var lanDiscovery: LANMumbleDiscovery?
    @ObservationIgnored private var globalShortcutConfiguration: ServerShortcutConfiguration?

    init(
        servers: [MumbleServer]? = nil,
        channels: [MumbleChannel] = [],
        connectionState: ConnectionState = .disconnected
    ) {
        let controlConnection = MumbleControlConnection()
        self.controlConnection = controlConnection
        voiceRouter = MumbleVoiceRouter(controlConnection: controlConnection)
        let resolvedServers = servers ?? SavedServerStore.load()
        self.servers = resolvedServers
        self.channels = channels
        self.connectionState = connectionState
        selectedServerID = resolvedServers.first?.id
        selectedChannelID = channels.first?.id
        let defaults = UserDefaults.standard
        let inputID = defaults.object(forKey: "selectedInputDeviceID") as? NSNumber
        let outputID = defaults.object(forKey: "selectedOutputDeviceID") as? NSNumber
        selectedInputDeviceID = inputID.map { UInt32(truncating: $0) }
        selectedOutputDeviceID = outputID.map { UInt32(truncating: $0) }
        loadClientIdentity()
        isGlobalPushToTalkEnabled = defaults.bool(forKey: "globalPushToTalkEnabled")
        if let shortcutData = defaults.data(forKey: "globalPushToTalkShortcut"),
           let shortcut = try? JSONDecoder().decode(GlobalHotKeyShortcut.self, from: shortcutData) {
            globalPushToTalkShortcut = shortcut
        }
        isPushToMuteEnabled = defaults.bool(forKey: "pushToMuteEnabled")
        if let data = defaults.data(forKey: "pushToMuteShortcut"),
           let shortcut = try? JSONDecoder().decode(GlobalHotKeyShortcut.self, from: data) {
            pushToMuteShortcut = shortcut
        }
        areGlobalAudioShortcutsEnabled = defaults.bool(forKey: "globalAudioShortcutsEnabled")
        if let data = defaults.data(forKey: "globalAudioShortcuts"),
           let shortcuts = try? JSONDecoder().decode([GlobalAudioShortcutAction: GlobalHotKeyShortcut].self, from: data) {
            globalAudioShortcuts.merge(shortcuts) { _, saved in saved }
        }
        idleAudioAction = IdleAudioAction(rawValue: defaults.string(forKey: "idleAudioAction") ?? "") ?? .none
        idleTimeoutMinutes = max(1, defaults.object(forKey: "idleTimeoutMinutes") as? Int ?? 10)
        isWhisperShortcutEnabled = defaults.bool(forKey: "whisperShortcutEnabled")
        if let data = defaults.data(forKey: "whisperShortcut"),
           let shortcut = try? JSONDecoder().decode(GlobalHotKeyShortcut.self, from: data) { whisperShortcut = shortcut }
        if let data = defaults.data(forKey: "configuredVoiceTarget") {
            configuredVoiceTarget = try? JSONDecoder().decode(ConfiguredVoiceTarget.self, from: data)
        }
        if let data = defaults.data(forKey: "serverShortcutOverrides"),
           let overrides = try? JSONDecoder().decode([String: ServerShortcutConfiguration].self, from: data) {
            serverShortcutOverrides = overrides
        }
        friendCertificateHashes = Set(defaults.stringArray(forKey: "friendCertificateHashes") ?? [])
        if let data = defaults.data(forKey: "localUserNicknames"),
           let nicknames = try? JSONDecoder().decode([String: String].self, from: data) { localUserNicknames = nicknames }
        ignoredMessageUserHashes = Set(defaults.stringArray(forKey: "ignoredMessageUserHashes") ?? [])
        ignoredTTSUserHashes = Set(defaults.stringArray(forKey: "ignoredTTSUserHashes") ?? [])
        doubleClickPTTTogglesContinuous = defaults.bool(forKey: "doubleClickPTTTogglesContinuous")
        transmissionMode = AudioTransmissionMode(
            rawValue: defaults.string(forKey: "audioTransmissionMode") ?? ""
        ) ?? .pushToTalk
        let savedThreshold = defaults.object(forKey: "voiceActivityThresholdDB") as? NSNumber
        voiceActivityThresholdDB = savedThreshold?.doubleValue ?? -35
        if let volumeData = defaults.data(forKey: "userVolumeGains"),
           let volumes = try? JSONDecoder().decode([String: Float].self, from: volumeData) {
            persistedUserVolumes = volumes
        }
        if let mutedUsers = defaults.array(forKey: "locallyMutedUsers") as? [String] {
            persistedMutedUsers = Set(mutedUsers)
        }
        autoReconnectEnabled = defaults.object(forKey: "autoReconnectEnabled") as? Bool ?? true
        unmuteOnUndeafen = defaults.object(forKey: "unmuteOnUndeafen") as? Bool ?? true
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        masterOutputVolume = (defaults.object(forKey: "masterOutputVolume") as? NSNumber)?.floatValue ?? 1
        duckingEnabled = defaults.bool(forKey: "duckingEnabled")
        duckingVolume = (defaults.object(forKey: "duckingVolume") as? NSNumber)?.floatValue ?? 0.35
        noiseSuppressionEnabled = defaults.bool(forKey: "noiseSuppressionEnabled")
        pushToTalkHoldMilliseconds = defaults.object(forKey: "pushToTalkHoldMilliseconds") as? Int ?? 0
        jitterBufferDelayFrames = defaults.object(forKey: "jitterBufferDelayFrames") as? Int ?? 3
        textToSpeechEnabled = defaults.bool(forKey: "textToSpeechEnabled")
        opusBitrateKbps = defaults.object(forKey: "opusBitrateKbps") as? Int ?? 40
        opusComplexity = defaults.object(forKey: "opusComplexity") as? Int ?? 8
        opusExpectedPacketLossPercent = defaults.object(forKey: "opusExpectedPacketLossPercent") as? Int ?? 5
        opusInbandFECEnabled = defaults.object(forKey: "opusInbandFECEnabled") as? Bool ?? true
        opusLowLatencyEnabled = defaults.bool(forKey: "opusLowLatencyEnabled")
        opusFramesPerPacket = [1, 2, 4, 6].contains(defaults.object(forKey: "opusFramesPerPacket") as? Int ?? 2)
            ? (defaults.object(forKey: "opusFramesPerPacket") as? Int ?? 2) : 2
        automaticGainControlEnabled = defaults.bool(forKey: "automaticGainControlEnabled")
        echoCancellationEnabled = defaults.bool(forKey: "echoCancellationEnabled")
        publicServerDirectoryEnabled = defaults.bool(forKey: "publicServerDirectoryEnabled")
        connectionTimeoutSeconds = min(120, max(5, defaults.object(forKey: "connectionTimeoutSeconds") as? Int ?? 15))
        controlPingIntervalSeconds = min(60, max(5, defaults.object(forKey: "controlPingIntervalSeconds") as? Int ?? 20))
        proxyType = MumbleProxyType(rawValue: defaults.string(forKey: "proxyType") ?? "") ?? .none
        proxyHost = defaults.string(forKey: "proxyHost") ?? ""
        proxyPort = UInt16(defaults.object(forKey: "proxyPort") as? Int ?? 1080)
        proxyUsername = defaults.string(forKey: "proxyUsername") ?? ""
        chatLogLimit = min(5_000, max(50, defaults.object(forKey: "chatLogLimit") as? Int ?? 500))
        chatUses24HourTime = defaults.bool(forKey: "chatUses24HourTime")
        channelExpansionPolicy = ChannelExpansionPolicy(rawValue: defaults.string(forKey: "channelExpansionPolicy") ?? "") ?? .currentPath
        showsReturnToPreviousChannelControl = defaults.bool(forKey: "showsReturnToPreviousChannelControl")
        showsHideEmptyChannelsControl = defaults.bool(forKey: "showsHideEmptyChannelsControl")
        audioCuesEnabled = defaults.bool(forKey: "audioCuesEnabled")
        hideEmptyChannels = defaults.bool(forKey: "hideEmptyChannels")
        if !showsHideEmptyChannelsControl { hideEmptyChannels = false }
        globalShortcutConfiguration = currentShortcutConfiguration
        applyShortcutConfigurationForSelectedServer(rebind: false)
        loadChannelPreferences()
        audioMixer.setMasterGain(masterOutputVolume)
        audioMixer.setDuckingGain(duckingVolume)
        if isGlobalPushToTalkEnabled { configureGlobalPushToTalk(enabled: true) }
        if isPushToMuteEnabled { configurePushToMute(enabled: true) }
        if areGlobalAudioShortcutsEnabled { configureGlobalAudioShortcuts(enabled: true) }
        if isWhisperShortcutEnabled { configureWhisperShortcut(enabled: true) }
        lanDiscovery = LANMumbleDiscovery { [weak self] servers in
            Task { @MainActor in self?.discoveredServers = servers }
        }
        lanDiscovery?.start()
        startIdleMonitor()
        if publicServerDirectoryEnabled { refreshPublicServers() }
    }

    var selectedServer: MumbleServer? {
        servers.first { $0.id == selectedServerID }
    }

    var selectedServerUsesShortcutOverride: Bool {
        guard let key = selectedServerID?.uuidString else { return false }
        return serverShortcutOverrides[key] != nil
    }

    private var currentShortcutConfiguration: ServerShortcutConfiguration {
        ServerShortcutConfiguration(
            pushToTalk: globalPushToTalkShortcut,
            pushToMute: pushToMuteShortcut,
            audio: globalAudioShortcuts,
            whisper: whisperShortcut
        )
    }

    var editingServer: MumbleServer? {
        guard let editingServerID else { return nil }
        return servers.first { $0.id == editingServerID }
    }

    var selectedChannel: MumbleChannel? {
        guard let selectedChannelID else { return nil }
        return findChannel(id: selectedChannelID, in: channels)
    }

    var flattenedChannels: [MumbleChannel] {
        flattenChannels(channels)
    }

    var talkingUserNames: [String] {
        flattenedChannels
            .flatMap(\.users)
            .filter(\.isTalking)
            .map(displayName(for:))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var visibleChannels: [MumbleChannel] {
        let required = requiredVisibleChannelIDs
        let filtered = channels.compactMap { filterChannel($0, required: required) }
        return filtered.sorted { lhs, rhs in
            let lhsPinned = pinnedChannelIDs.contains(lhs.id)
            let rhsPinned = pinnedChannelIDs.contains(rhs.id)
            return lhsPinned == rhsPinned ? channelSort(lhs, rhs) : lhsPinned
        }
    }

    func setHideEmptyChannels(_ hidden: Bool) {
        hideEmptyChannels = hidden
        UserDefaults.standard.set(hidden, forKey: "hideEmptyChannels")
    }

    func setShowsReturnToPreviousChannelControl(_ visible: Bool) {
        showsReturnToPreviousChannelControl = visible
        UserDefaults.standard.set(visible, forKey: "showsReturnToPreviousChannelControl")
    }

    func setShowsHideEmptyChannelsControl(_ visible: Bool) {
        showsHideEmptyChannelsControl = visible
        UserDefaults.standard.set(visible, forKey: "showsHideEmptyChannelsControl")
        if !visible { setHideEmptyChannels(false) }
    }

    func toggleChannelHidden(_ channel: MumbleChannel) {
        if hiddenChannelIDs.remove(channel.id) == nil { hiddenChannelIDs.insert(channel.id) }
        persistChannelPreferences()
    }

    func toggleChannelPinned(_ channel: MumbleChannel) {
        if pinnedChannelIDs.remove(channel.id) == nil { pinnedChannelIDs.insert(channel.id) }
        persistChannelPreferences()
    }
    func isChannelExpanded(_ channel: MumbleChannel) -> Bool { expandedChannelIDs.contains(channel.id) }
    func setChannelExpanded(_ channel: MumbleChannel, expanded: Bool) {
        if expanded { expandedChannelIDs.insert(channel.id) } else { expandedChannelIDs.remove(channel.id) }
    }
    func setChannelExpansionPolicy(_ policy: ChannelExpansionPolicy) {
        channelExpansionPolicy = policy; UserDefaults.standard.set(policy.rawValue, forKey: "channelExpansionPolicy")
        applyChannelExpansionPolicy()
    }
    private func applyChannelExpansionPolicy() {
        switch channelExpansionPolicy {
        case .all: expandedChannelIDs = Set(flattenedChannels.map(\.id))
        case .collapsed: expandedChannelIDs = Set(channels.map(\.id))
        case .currentPath:
            let ownChannel: UInt32?
            if case .connected(let session) = connectionState {
                ownChannel = flattenedChannels.flatMap(\.users).first { $0.id == session }?.channelID
            } else { ownChannel = nil }
            let target = selectedChannelID ?? ownChannel
            guard let target else { return }
            expandedChannelIDs = requiredVisibleChannelIDs.union([target])
        }
    }

    func jumpToUser(_ user: MumbleUser) {
        selectedChannelID = user.channelID
        var current = flattenedChannels.first { $0.id == user.channelID }
        while let channel = current {
            expandedChannelIDs.insert(channel.id)
            current = channel.parentID.flatMap { id in flattenedChannels.first { $0.id == id } }
        }
    }

    func moveUser(_ user: MumbleUser, to channel: MumbleChannel) { sendMoveUser(user.id, to: channel.id) }

    func moveChannel(_ channel: MumbleChannel, to parent: MumbleChannel) {
        guard channel.id != parent.id, channel.parentID != nil,
              !descendantIDs(of: channel).contains(parent.id) else { return }
        Task { try? await controlConnection.send(MumbleCommands.moveChannel(channelID: channel.id, toParent: parent.id)) }
    }

    private func sendMoveUser(_ session: UInt32, to channelID: UInt32) {
        guard case .connected = connectionState else { return }
        Task { try? await controlConnection.send(MumbleCommands.moveUser(session: session, toChannel: channelID)) }
    }

    private var channelPreferencePrefix: String { "channelPreferences.\(selectedServerID?.uuidString ?? "none")" }

    private func persistChannelPreferences() {
        UserDefaults.standard.set(hiddenChannelIDs.map(String.init), forKey: "\(channelPreferencePrefix).hidden")
        UserDefaults.standard.set(pinnedChannelIDs.map(String.init), forKey: "\(channelPreferencePrefix).pinned")
    }

    private func loadChannelPreferences() {
        let defaults = UserDefaults.standard
        hiddenChannelIDs = Set((defaults.stringArray(forKey: "\(channelPreferencePrefix).hidden") ?? []).compactMap(UInt32.init))
        pinnedChannelIDs = Set((defaults.stringArray(forKey: "\(channelPreferencePrefix).pinned") ?? []).compactMap(UInt32.init))
    }

    private var requiredVisibleChannelIDs: Set<UInt32> {
        var required = Set(listeningChannelIDs).union(pinnedChannelIDs)
        if let selectedChannelID { required.insert(selectedChannelID) }
        if case .connected(let session) = connectionState,
           let own = flattenedChannels.flatMap(\.users).first(where: { $0.id == session }) { required.insert(own.channelID) }
        var result = required
        for id in required {
            var current = flattenedChannels.first { $0.id == id }
            while let parent = current?.parentID {
                result.insert(parent)
                current = flattenedChannels.first { $0.id == parent }
            }
        }
        return result
    }

    private func filterChannel(_ channel: MumbleChannel, required: Set<UInt32>) -> MumbleChannel? {
        var copy = channel
        copy.children = channel.children.compactMap { filterChannel($0, required: required) }
            .sorted(by: channelSort)
        let explicitlyHidden = hiddenChannelIDs.contains(channel.id) && !required.contains(channel.id)
        let empty = channel.users.isEmpty && copy.children.isEmpty
        if explicitlyHidden || (hideEmptyChannels && empty && !required.contains(channel.id) && channel.parentID != nil) { return nil }
        return copy
    }

    private func channelSort(_ lhs: MumbleChannel, _ rhs: MumbleChannel) -> Bool {
        lhs.position == rhs.position
            ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            : lhs.position < rhs.position
    }

    private func descendantIDs(of channel: MumbleChannel) -> Set<UInt32> {
        Set(flattenChannels(channel.children).map(\.id))
    }

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
        guard case .connected = connectionState else { return connectionLabel }
        return isUsingUDP ? L10n.text("connection.udp") : L10n.text("connection.tcp")
    }

    var activeReceivePipelineCount: Int { audioReceivePipelines.count }
    var averageReceiveJitterMilliseconds: Double {
        guard !audioReceivePipelines.isEmpty else { return 0 }
        return audioReceivePipelines.values.map(\.estimatedJitterMilliseconds).reduce(0, +)
            / Double(audioReceivePipelines.count)
    }
    var averageReceiveBufferMilliseconds: Int {
        guard !audioReceivePipelines.isEmpty else { return jitterBufferDelayFrames * 10 }
        return audioReceivePipelines.values.map(\.targetDelayFrames).reduce(0, +) * 10
            / audioReceivePipelines.count
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
        noiseSuppressor.reset()
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
        automaticGainControl.reset()
        UserDefaults.standard.set(enabled, forKey: "automaticGainControlEnabled")
    }
    func setEchoCancellationEnabled(_ enabled: Bool) {
        echoCancellationEnabled = enabled; echoCanceller.reset()
        UserDefaults.standard.set(enabled, forKey: "echoCancellationEnabled")
    }

    func setAudioCuesEnabled(_ enabled: Bool) {
        audioCuesEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "audioCuesEnabled")
    }

    private var opusEncoderConfiguration: OpusEncoderConfiguration {
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

    private func setTransmitting(_ transmitting: Bool) {
        let changed = transmitting != isTransmitting
        isTransmitting = transmitting
        audioMixer.setDuckingActive(duckingEnabled && transmitting)
        if changed, audioCuesEnabled {
            audioCueService.play(transmitting ? .transmitStart : .transmitStop)
        }
        if changed { rebuildChannels() }
    }

    func connect(password: String? = nil, isReconnect: Bool = false) {
        guard let server = selectedServer else {
            connectionState = .failed(message: L10n.text("server.selectFirst"))
            return
        }

        if !isReconnect {
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectPolicy.reset()
            isReconnecting = false
            reconnectAttempt = 0
            reconnectServerID = server.id
        }
        suppressReconnect = false
        didSynchronize = false
        connectionTask?.cancel()
        pingTask?.cancel()
        protocolState = MumbleServerState()
        serverContextActions = []
        serverSuggestedPushToTalk = nil
        serverSuggestedPositionalAudio = nil
        serverSuggestedVersion = nil
        stopUDP()
        serverProtocolVersion = MumbleProtocolVersion(major: 1, minor: 4, patch: 0)
        channels = []
        serverWelcomeText = ""
        if !isReconnect { chatEntries = [] }
        serverRecognizedIdentityHash = nil
        connectionState = .connecting

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

        connectionTask = Task {
            let pin = server.certificateFingerprint
                .flatMap(MumbleCertificateFingerprint.init(hex:))?
                .bytes
            let events = await controlConnection.connect(
                host: server.host,
                port: server.port,
                pinnedCertificateSHA256: pin,
                clientIdentity: clientIdentity,
                connectionTimeoutSeconds: UInt32(connectionTimeoutSeconds),
                proxy: proxyConfiguration
            )

            for await event in events {
                guard !Task.isCancelled else { return }

                switch event {
                case .preparing:
                    connectionState = .connecting

                case .ready:
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
                        fingerprint: fingerprint
                    )
                    connectionState = .failed(message: L10n.text("certificate.confirmRequired"))

                case .failed(let message):
                    if pendingServerCertificate == nil {
                        connectionState = .failed(message: message)
                    }
                    pingTask?.cancel()
                    scheduleReconnectIfNeeded()

                case .disconnected:
                    pingTask?.cancel()
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
                    if audioCuesEnabled, didSynchronize { audioCueService.play(.disconnected) }
                    scheduleReconnectIfNeeded()
                }
            }
        }
    }

    func handleServerDoubleClick(_ server: MumbleServer) {
        switch connectionState {
        case .connecting, .authenticating, .connected:
            return
        case .disconnected, .failed:
            selectedServerID = server.id
            connect()
        }
    }

    func openMumbleURL(_ url: URL) {
        guard let target = MumbleURL(url: url) else {
            serverManagementError = L10n.text("server.url.invalid")
            return
        }
        if let existing = servers.first(where: { $0.host.caseInsensitiveCompare(target.host) == .orderedSame && $0.port == target.port }) {
            selectedServerID = existing.id
        } else {
            let server = MumbleServer(name: target.host, host: target.host, port: target.port, username: target.username ?? "")
            servers.append(server)
            SavedServerStore.save(servers)
            selectedServerID = server.id
        }
        pendingChannelPath = target.channelPath
        connect()
    }

    func serverURL() -> URL? {
        guard let server = selectedServer else { return nil }
        return MumbleURL(host: server.host, port: server.port, username: server.username).url
    }

    func channelURL(_ channel: MumbleChannel) -> URL? {
        guard let server = selectedServer else { return nil }
        return MumbleURL(host: server.host, port: server.port, username: server.username, channelPath: path(to: channel.id)).url
    }

    func copyURL(_ url: URL?) {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func connectToDiscoveredServer(_ discovered: DiscoveredMumbleServer) {
        if let existing = servers.first(where: { $0.host == discovered.host && $0.port == discovered.port }) {
            selectedServerID = existing.id
        } else {
            let server = MumbleServer(name: discovered.name, host: discovered.host, port: discovered.port)
            servers.append(server)
            SavedServerStore.save(servers)
            selectedServerID = server.id
        }
        connect()
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

    private var proxyConfiguration: MumbleProxyConfiguration {
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

    private func path(to channelID: UInt32) -> [String] {
        var names: [String] = []
        var current = flattenedChannels.first { $0.id == channelID }
        while let channel = current, channel.parentID != nil {
            names.insert(channel.name, at: 0)
            current = channel.parentID.flatMap { id in flattenedChannels.first { $0.id == id } }
        }
        return names
    }

    private func joinPendingChannelPath() {
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
        servers.append(server)
        SavedServerStore.save(servers)
        selectedServerID = server.id
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
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }

        if selectedServerID == server.id, connectionState != .disconnected {
            disconnect()
        }

        servers[index] = server
        SavedServerStore.save(servers)
        updateStoredPassword(for: server.id, password: password, shouldSave: savePassword)
        updateStoredAccessTokens(for: server.id, tokens: accessTokens)
    }

    func deleteServer(_ server: MumbleServer) {
        if selectedServerID == server.id {
            disconnect()
        }

        servers.removeAll { $0.id == server.id }
        SavedServerStore.save(servers)
        selectedServerID = servers.first?.id
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

    private func loadClientIdentity() {
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

    private func updateStoredPassword(
        for serverID: MumbleServer.ID,
        password: String,
        shouldSave: Bool
    ) {
        do {
            if shouldSave, !password.isEmpty {
                try KeychainPasswordStore.save(password, account: serverID.uuidString)
            } else if !shouldSave {
                try KeychainPasswordStore.delete(account: serverID.uuidString)
            }
        } catch {
            serverManagementError = L10n.text("keychain.updateError", error.localizedDescription)
        }
    }

    private func updateStoredAccessTokens(for serverID: MumbleServer.ID, tokens: [String]) {
        do {
            try KeychainAccessTokenStore.save(tokens, account: serverID.uuidString)
        } catch {
            serverManagementError = L10n.text("keychain.tokensUpdateError", error.localizedDescription)
        }
    }

    func trustPendingServerCertificate() {
        guard let pendingServerCertificate,
              let index = servers.firstIndex(where: { $0.id == pendingServerCertificate.serverID }) else {
            return
        }

        servers[index].certificateFingerprint = pendingServerCertificate.fingerprint.hex
        SavedServerStore.save(servers)
        self.pendingServerCertificate = nil
        connect(password: pendingConnectionPassword)
    }

    func cancelPendingServerCertificate() {
        pendingServerCertificate = nil
        disconnect()
    }

    func disconnect() {
        cancelAudioLoopbackTest()
        // User-initiated: stop any pending reconnect and don't schedule new ones.
        suppressReconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        reconnectAttempt = 0
        reconnectPolicy.reset()
        stopAutomaticAudioCapture()
        endTransmission()
        stopUDP()
        audioPlayback?.stop()
        audioPlayback = nil
        audioDrainTasks.values.forEach { $0.cancel() }
        audioDrainTasks.removeAll()
        audioReceivePipelines.removeAll()
        audioMixTask?.cancel()
        audioMixTask = nil
        audioMixer.removeAllSources()
        userVolumeGains.removeAll()
        locallyMutedSessions.removeAll()
        talkingPruneTask?.cancel()
        talkingPruneTask = nil
        talkingTracker.reset()
        channelSnapshot = []
        channelHistory.reset()
        listeningChannelIDs.removeAll()
        listeningChannelVolumes.removeAll()
        clearDisconnectedSessionPresentation()
        connectionTask?.cancel()
        connectionTask = nil
        pingTask?.cancel()
        pingTask = nil
        connectionState = .disconnected
        Task { await controlConnection.disconnect() }
        refreshAutomaticAudioCapture()
    }

    private func clearDisconnectedSessionPresentation() {
        protocolState = MumbleServerState()
        channels = []
        selectedChannelID = nil
        expandedChannelIDs.removeAll()
        serverWelcomeText = ""
        chatEntries.removeAll()
        chatDraft = ""
        privateMessageTarget = nil
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
        serverMaximumUsers = nil
        serverMaximumBandwidth = nil
    }

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
                let frameStream = AsyncStream.makeStream(of: [Float].self)
                manualFrameContinuation = frameStream.continuation
                let frameContinuation = frameStream.continuation
                manualFrameConsumerTask = Task { [weak self] in
                    for await samples in frameStream.stream {
                        guard let self,
                              generation == self.manualCaptureGeneration,
                              self.isTransmitting,
                              self.transmissionMode == .pushToTalk,
                              case .connected = self.connectionState else { return }
                        self.sendCapturedFrame(self.processedInput(samples), alreadyProcessed: true)
                    }
                }
                try audioCapture.start { samples in
                    frameContinuation.yield(samples)
                }
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

    private func finishTransmitPipeline() {
        guard isTransmitting else { return }
        publishPendingAudioPacketCount()
        setTransmitting(false)
        let voiceRouter = voiceRouter
        let target = activeVoiceTargetID
        let protocolVersion = serverProtocolVersion
        transmitEncodingQueue.finish { frameNumber in
            guard let frameNumber else { return }
            Task {
                if let packet = try? MumbleVoicePacket.clientAudioPacket(
                    opusData: Data(),
                    frameNumber: frameNumber,
                    target: target,
                    isTerminator: true,
                    protocolVersion: protocolVersion
                ) {
                    try? await voiceRouter.send(packet)
                }
            }
        }
        activeVoiceTargetID = 0
    }

    private func sendCapturedFrame(_ samples: [Float], alreadyProcessed: Bool = false) {
        let samples = alreadyProcessed ? samples : processedInput(samples)
        if !isTransmitting { setTransmitting(true) }
        let configuration = opusEncoderConfiguration
        let framesPerPacket = opusFramesPerPacket
        let target = activeVoiceTargetID
        let protocolVersion = serverProtocolVersion
        let voiceRouter = voiceRouter
        transmitEncodingQueue.enqueue(
            samples: samples,
            configuration: configuration,
            framesPerPacket: framesPerPacket
        ) { [weak self] result in
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
                    Task {
                        do {
                            try await voiceRouter.send(packet)
                            self?.recordAudioPacketSent()
                        } catch {
                            self?.handleTransmitFailure(error.localizedDescription)
                        }
                    }
                } catch {
                    self?.handleTransmitFailure(error.localizedDescription)
                }
            case .failed(let error):
                self?.handleTransmitFailure(String(describing: error))
            }
        }
    }

    private func handleTransmitFailure(_ message: String) {
        audioErrorMessage = message
        finishTransmitPipeline()
    }

    private func recordAudioPacketSent() {
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

    private func publishPendingAudioPacketCount() {
        guard unpublishedAudioPacketsSent > 0 else { return }
        audioPacketsSent += unpublishedAudioPacketsSent
        unpublishedAudioPacketsSent = 0
    }

    private func processedInput(_ samples: [Float]) -> [Float] {
        let echoReduced = echoCancellationEnabled ? echoCanceller.process(samples) : samples
        let denoised = noiseSuppressionEnabled ? noiseSuppressor.process(echoReduced) : echoReduced
        return automaticGainControlEnabled ? automaticGainControl.process(denoised) : denoised
    }

    func setTransmissionMode(_ mode: AudioTransmissionMode) {
        guard transmissionMode != mode else { return }
        stopAutomaticAudioCapture()
        endTransmission()
        transmissionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "audioTransmissionMode")
        refreshAutomaticAudioCapture()
    }

    func setVoiceActivityThresholdDB(_ threshold: Double) {
        voiceActivityThresholdDB = min(-5, max(-70, threshold))
        UserDefaults.standard.set(voiceActivityThresholdDB, forKey: "voiceActivityThresholdDB")
    }

    func setAudioSettingsVisible(_ visible: Bool) {
        isAudioSettingsVisible = visible
        if !visible { cancelAudioLoopbackTest() }
        refreshAutomaticAudioCapture()
    }

    private func refreshAutomaticAudioCapture() {
        if shouldAutomaticallyMonitorMicrophone {
            startAutomaticAudioCapture()
        } else {
            stopAutomaticAudioCapture()
        }
    }

    private var shouldAutomaticallyMonitorMicrophone: Bool {
        let connected: Bool
        if case .connected = connectionState { connected = true } else { connected = false }
        return transmissionMode != .pushToTalk && (connected || isAudioSettingsVisible)
    }

    private func startAutomaticAudioCapture() {
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
                audioCapture.selectDevice(selectedInputDeviceID)
                let frameStream = AsyncStream.makeStream(of: [Float].self)
                automaticFrameContinuation = frameStream.continuation
                let frameContinuation = frameStream.continuation
                automaticFrameConsumerTask = Task { [weak self] in
                    for await samples in frameStream.stream {
                        guard let self,
                              generation == self.automaticCaptureGeneration,
                              self.shouldAutomaticallyMonitorMicrophone else { return }
                        let processed = self.processedInput(samples)
                        self.handleAutomaticCapturedFrame(
                            processed,
                            levelDB: AudioLevelMeter.decibels(samples: processed)
                        )
                    }
                }
                try audioCapture.start { samples in
                    frameContinuation.yield(samples)
                }
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

    private func stopAutomaticAudioCapture() {
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
        isVoiceActivityDetected = false
        voiceActivityGate.reset()
        levelSmoother.reset()
        finishTransmitPipeline()
    }

    private func handleAutomaticCapturedFrame(_ samples: [Float], levelDB: Double) {
        guard transmissionMode != .pushToTalk else { return }
        let smoothedLevel = levelSmoother.process(levelDB: levelDB)
        microphoneLevelFrameCounter += 1
        if microphoneLevelFrameCounter.isMultiple(of: 3) {
            microphoneLevelDB = smoothedLevel
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
        // Learn the ambient noise floor only from frames the gate treats as
        // silence, so speech does not pull the estimate up.
        if transmissionMode == .voiceActivity, !shouldSend {
            noiseFloorDB = noiseFloorTracker.observeSilence(levelDB: smoothedLevel)
        }

        guard case .connected = connectionState, !isMuted else {
            finishTransmitPipeline()
            return
        }
        if shouldSend {
            sendCapturedFrame(samples, alreadyProcessed: true)
        } else {
            finishTransmitPipeline()
        }
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        if muted { endTransmission() }
        isMuted = muted
        if audioCuesEnabled { audioCueService.play(muted ? .muted : .unmuted) }
        // Unmuting while deafened makes no sense; drop deafen too.
        if !muted, isDeafened { isDeafened = false }
        syncSelfAudioState()
    }

    func toggleDeafen() {
        setDeafened(!isDeafened)
    }

    func setDeafened(_ deafened: Bool) {
        guard deafened != isDeafened else { return }
        isDeafened = deafened
        if deafened {
            // Deafen implies mute, matching official behavior.
            if !isMuted { endTransmission() }
            isMuted = true
        } else if unmuteOnUndeafen {
            isMuted = false
        }
        syncSelfAudioState()
    }

    /// Reconciles local mute/deafen with the server's authoritative view (e.g.
    /// after reconnect or when another session changed it). Does not re-send, to
    /// avoid a feedback loop with our own echoed UserState.
    private func applyServerSelfState(_ user: MumbleUser) {
        if user.isSelfMuted != isMuted {
            if user.isSelfMuted { endTransmission() }
            isMuted = user.isSelfMuted
        }
        if user.isSelfDeafened != isDeafened {
            isDeafened = user.isSelfDeafened
        }
    }

    /// Pushes the current self-mute/deafen state to the server when connected.
    private func syncSelfAudioState() {
        guard case .connected(let session) = connectionState else { return }
        reportSelfAudioState(session: session)
    }

    private func reportSelfAudioState(session: UInt32) {
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
        autoReconnectEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "autoReconnectEnabled")
        if !enabled {
            reconnectTask?.cancel()
            reconnectTask = nil
            isReconnecting = false
            reconnectAttempt = 0
        }
    }

    func setUnmuteOnUndeafen(_ enabled: Bool) {
        unmuteOnUndeafen = enabled
        UserDefaults.standard.set(enabled, forKey: "unmuteOnUndeafen")
    }

    private func scheduleReconnectIfNeeded() {
        guard autoReconnectEnabled,
              !suppressReconnect,
              reconnectTask == nil,
              let serverID = reconnectServerID,
              selectedServerID == serverID,
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
                  selectedServerID == serverID else {
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

    private func persistUserVolumes() {
        if let data = try? JSONEncoder().encode(persistedUserVolumes) {
            UserDefaults.standard.set(data, forKey: "userVolumeGains")
        }
    }

    /// Applies any live or persisted volume/mute preference for a speaker to the
    /// mixer as soon as their audio source is registered.
    private func seedMixerSettings(session: UInt32) {
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

    func setSelectedServerShortcutOverrideEnabled(_ enabled: Bool) {
        guard let key = selectedServerID?.uuidString else { return }
        if enabled {
            serverShortcutOverrides[key] = currentShortcutConfiguration
        } else {
            serverShortcutOverrides.removeValue(forKey: key)
        }
        persistServerShortcutOverrides()
        applyShortcutConfigurationForSelectedServer()
    }

    private func persistActiveShortcutConfiguration() {
        let configuration = currentShortcutConfiguration
        if let key = selectedServerID?.uuidString, serverShortcutOverrides[key] != nil {
            serverShortcutOverrides[key] = configuration
            persistServerShortcutOverrides()
        } else {
            globalShortcutConfiguration = configuration
        }
    }

    private func persistServerShortcutOverrides() {
        if let data = try? JSONEncoder().encode(serverShortcutOverrides) {
            UserDefaults.standard.set(data, forKey: "serverShortcutOverrides")
        }
    }

    private func applyShortcutConfigurationForSelectedServer(rebind: Bool = true) {
        guard let fallback = globalShortcutConfiguration else { return }
        let configuration = selectedServerID.flatMap { serverShortcutOverrides[$0.uuidString] } ?? fallback
        globalPushToTalkShortcut = configuration.pushToTalk
        pushToMuteShortcut = configuration.pushToMute
        globalAudioShortcuts = configuration.audio
        whisperShortcut = configuration.whisper
        guard rebind else { return }
        do {
            try globalPushToTalkHotKey?.setShortcut(configuration.pushToTalk)
            try pushToMuteHotKey?.setShortcut(configuration.pushToMute)
            for action in GlobalAudioShortcutAction.allCases {
                if let shortcut = configuration.audio[action] {
                    try globalAudioHotKeys[action]?.setShortcut(shortcut)
                }
            }
            try whisperHotKey?.setShortcut(configuration.whisper)
            globalPushToTalkError = nil
        } catch {
            globalPushToTalkError = error.localizedDescription
        }
    }

    func setGlobalPushToTalkEnabled(_ enabled: Bool) {
        configureGlobalPushToTalk(enabled: enabled)
        if globalPushToTalkError == nil {
            isGlobalPushToTalkEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: "globalPushToTalkEnabled")
        }
    }

    func setGlobalPushToTalkShortcut(_ shortcut: GlobalHotKeyShortcut) {
        do {
            if globalPushToTalkHotKey == nil {
                globalPushToTalkHotKey = try makeGlobalPushToTalkHotKey(shortcut: shortcut)
            } else {
                try globalPushToTalkHotKey?.setShortcut(shortcut)
            }
            globalPushToTalkShortcut = shortcut
            persistActiveShortcutConfiguration()
            if let data = try? JSONEncoder().encode(shortcut) {
                if !selectedServerUsesShortcutOverride { UserDefaults.standard.set(data, forKey: "globalPushToTalkShortcut") }
            }
            globalPushToTalkError = nil
        } catch {
            isGlobalPushToTalkEnabled = false
            UserDefaults.standard.set(false, forKey: "globalPushToTalkEnabled")
            globalPushToTalkError = error.localizedDescription
        }
    }

    func setRecordingGlobalShortcut(_ recording: Bool) {
        isRecordingGlobalShortcut = recording
        guard isGlobalPushToTalkEnabled else { return }
        do {
            try globalPushToTalkHotKey?.setEnabled(!recording)
            globalPushToTalkError = nil
        } catch {
            isGlobalPushToTalkEnabled = false
            UserDefaults.standard.set(false, forKey: "globalPushToTalkEnabled")
            globalPushToTalkError = error.localizedDescription
        }
    }

    func setPushToMuteEnabled(_ enabled: Bool) {
        configurePushToMute(enabled: enabled)
        if globalPushToTalkError == nil {
            isPushToMuteEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: "pushToMuteEnabled")
        }
    }

    func setPushToMuteShortcut(_ shortcut: GlobalHotKeyShortcut) {
        do {
            if pushToMuteHotKey == nil { pushToMuteHotKey = try makePushToMuteHotKey(shortcut: shortcut) }
            else { try pushToMuteHotKey?.setShortcut(shortcut) }
            pushToMuteShortcut = shortcut
            persistActiveShortcutConfiguration()
            if !selectedServerUsesShortcutOverride, let data = try? JSONEncoder().encode(shortcut) { UserDefaults.standard.set(data, forKey: "pushToMuteShortcut") }
            globalPushToTalkError = nil
        } catch { globalPushToTalkError = error.localizedDescription }
    }

    func setRecordingPushToMuteShortcut(_ recording: Bool) {
        guard isPushToMuteEnabled else { return }
        do { try pushToMuteHotKey?.setEnabled(!recording) }
        catch { globalPushToTalkError = error.localizedDescription }
    }

    private func configurePushToMute(enabled: Bool) {
        do {
            if pushToMuteHotKey == nil { pushToMuteHotKey = try makePushToMuteHotKey(shortcut: pushToMuteShortcut) }
            try pushToMuteHotKey?.setEnabled(enabled)
            if !enabled { releasePushToMute() }
            globalPushToTalkError = nil
        } catch {
            isPushToMuteEnabled = false
            UserDefaults.standard.set(false, forKey: "pushToMuteEnabled")
            globalPushToTalkError = error.localizedDescription
        }
    }

    private func makePushToMuteHotKey(shortcut: GlobalHotKeyShortcut) throws -> GlobalPushToTalkHotKey {
        try GlobalPushToTalkHotKey(shortcut: shortcut, identifierID: 2) { [weak self] pressed in
            guard let self else { return }
            if pressed {
                muteStateBeforePushToMute = isMuted
                endTransmission()
                setMuted(true)
            } else { releasePushToMute() }
        }
    }

    private func releasePushToMute() {
        guard isMuted != muteStateBeforePushToMute else { return }
        setMuted(muteStateBeforePushToMute)
    }

    func setGlobalAudioShortcutsEnabled(_ enabled: Bool) {
        configureGlobalAudioShortcuts(enabled: enabled)
        if globalPushToTalkError == nil {
            areGlobalAudioShortcutsEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: "globalAudioShortcutsEnabled")
        }
    }

    func setGlobalAudioShortcut(_ shortcut: GlobalHotKeyShortcut, for action: GlobalAudioShortcutAction) {
        do {
            if let hotKey = globalAudioHotKeys[action] { try hotKey.setShortcut(shortcut) }
            else { globalAudioHotKeys[action] = try makeGlobalAudioHotKey(action, shortcut: shortcut) }
            globalAudioShortcuts[action] = shortcut
            persistActiveShortcutConfiguration()
            if !selectedServerUsesShortcutOverride, let data = try? JSONEncoder().encode(globalAudioShortcuts) {
                UserDefaults.standard.set(data, forKey: "globalAudioShortcuts")
            }
            globalPushToTalkError = nil
        } catch { globalPushToTalkError = error.localizedDescription }
    }

    func setRecordingGlobalAudioShortcut(_ recording: Bool) {
        guard areGlobalAudioShortcutsEnabled else { return }
        do {
            for hotKey in globalAudioHotKeys.values { try hotKey.setEnabled(!recording) }
            globalPushToTalkError = nil
        } catch { globalPushToTalkError = error.localizedDescription }
    }

    private func configureGlobalAudioShortcuts(enabled: Bool) {
        do {
            for action in GlobalAudioShortcutAction.allCases {
                if globalAudioHotKeys[action] == nil, let shortcut = globalAudioShortcuts[action] {
                    globalAudioHotKeys[action] = try makeGlobalAudioHotKey(action, shortcut: shortcut)
                }
                try globalAudioHotKeys[action]?.setEnabled(enabled)
            }
            globalPushToTalkError = nil
        } catch {
            globalAudioHotKeys.values.forEach { try? $0.setEnabled(false) }
            areGlobalAudioShortcutsEnabled = false
            UserDefaults.standard.set(false, forKey: "globalAudioShortcutsEnabled")
            globalPushToTalkError = error.localizedDescription
        }
    }

    private func makeGlobalAudioHotKey(
        _ action: GlobalAudioShortcutAction,
        shortcut: GlobalHotKeyShortcut
    ) throws -> GlobalPushToTalkHotKey {
        try GlobalPushToTalkHotKey(shortcut: shortcut, identifierID: action.hotKeyID) { [weak self] pressed in
            guard pressed, let self else { return }
            performGlobalAudioShortcut(action)
        }
    }

    private func performGlobalAudioShortcut(_ action: GlobalAudioShortcutAction) {
        switch action {
        case .toggleMute: toggleMute()
        case .toggleDeafen: toggleDeafen()
        case .volumeDown: setMasterOutputVolume(masterOutputVolume - 0.05)
        case .volumeUp: setMasterOutputVolume(masterOutputVolume + 0.05)
        case .cycleTransmissionMode:
            let modes = AudioTransmissionMode.allCases
            let index = modes.firstIndex(of: transmissionMode) ?? 0
            setTransmissionMode(modes[(index + 1) % modes.count])
        }
    }

    func setIdleAudioAction(_ action: IdleAudioAction) {
        idleAudioAction = action
        didPerformIdleAction = false
        UserDefaults.standard.set(action.rawValue, forKey: "idleAudioAction")
    }

    func setIdleTimeoutMinutes(_ minutes: Int) {
        idleTimeoutMinutes = min(240, max(1, minutes))
        didPerformIdleAction = false
        UserDefaults.standard.set(idleTimeoutMinutes, forKey: "idleTimeoutMinutes")
    }

    private func startIdleMonitor() {
        idleMonitorTask?.cancel()
        idleMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, idleAudioAction != .none else { continue }
                let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
                if seconds < Double(idleTimeoutMinutes * 60) {
                    didPerformIdleAction = false
                } else if !didPerformIdleAction {
                    didPerformIdleAction = true
                    switch idleAudioAction {
                    case .none: break
                    case .mute: setMuted(true)
                    case .deafen: setDeafened(true)
                    }
                }
            }
        }
    }

    func setWhisperTarget(user: MumbleUser) {
        configuredVoiceTarget = .user(session: user.id, name: user.name)
        persistVoiceTarget()
    }

    func setWhisperTarget(channel: MumbleChannel, links: Bool, children: Bool) {
        configuredVoiceTarget = .channel(id: channel.id, name: channel.name, links: links, children: children)
        persistVoiceTarget()
    }

    func clearWhisperTarget() {
        configuredVoiceTarget = nil
        UserDefaults.standard.removeObject(forKey: "configuredVoiceTarget")
    }

    private func persistVoiceTarget() {
        if let data = try? JSONEncoder().encode(configuredVoiceTarget) {
            UserDefaults.standard.set(data, forKey: "configuredVoiceTarget")
        }
    }

    func setWhisperShortcutEnabled(_ enabled: Bool) {
        configureWhisperShortcut(enabled: enabled)
        if globalPushToTalkError == nil {
            isWhisperShortcutEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: "whisperShortcutEnabled")
        }
    }

    func setWhisperShortcut(_ shortcut: GlobalHotKeyShortcut) {
        do {
            if whisperHotKey == nil { whisperHotKey = try makeWhisperHotKey(shortcut) }
            else { try whisperHotKey?.setShortcut(shortcut) }
            whisperShortcut = shortcut
            persistActiveShortcutConfiguration()
            if !selectedServerUsesShortcutOverride, let data = try? JSONEncoder().encode(shortcut) { UserDefaults.standard.set(data, forKey: "whisperShortcut") }
            globalPushToTalkError = nil
        } catch { globalPushToTalkError = error.localizedDescription }
    }

    func setRecordingWhisperShortcut(_ recording: Bool) {
        guard isWhisperShortcutEnabled else { return }
        do { try whisperHotKey?.setEnabled(!recording) }
        catch { globalPushToTalkError = error.localizedDescription }
    }

    private func configureWhisperShortcut(enabled: Bool) {
        do {
            if whisperHotKey == nil { whisperHotKey = try makeWhisperHotKey(whisperShortcut) }
            try whisperHotKey?.setEnabled(enabled)
            if !enabled, activeVoiceTargetID != 0 { endTransmission() }
            globalPushToTalkError = nil
        } catch {
            isWhisperShortcutEnabled = false
            UserDefaults.standard.set(false, forKey: "whisperShortcutEnabled")
            globalPushToTalkError = error.localizedDescription
        }
    }

    private func makeWhisperHotKey(_ shortcut: GlobalHotKeyShortcut) throws -> GlobalPushToTalkHotKey {
        try GlobalPushToTalkHotKey(shortcut: shortcut, identifierID: 20) { [weak self] pressed in
            guard let self else { return }
            isWhisperPressed = pressed
            if pressed { beginWhisperTransmission() }
            else if activeVoiceTargetID == 1 {
                if isTransmitting { endTransmission() }
                else { activeVoiceTargetID = 0 }
            }
        }
    }

    private func beginWhisperTransmission() {
        guard let configuredVoiceTarget, !isMuted, case .connected = connectionState,
              transmissionMode == .pushToTalk, !isTransmitting else { return }
        let frame: MumbleFrame?
        switch configuredVoiceTarget {
        case .user(let session, _): frame = try? MumbleCommands.setVoiceTarget(id: 1, sessions: [session])
        case .channel(let id, _, let links, let children):
            frame = try? MumbleCommands.setVoiceTarget(id: 1, channelID: id, includeLinks: links, includeChildren: children)
        }
        guard let frame else { return }
        activeVoiceTargetID = 1
        Task {
            do {
                try await controlConnection.send(frame)
                guard isWhisperPressed else {
                    activeVoiceTargetID = 0
                    return
                }
                beginTransmission()
            } catch {
                activeVoiceTargetID = 0
                audioErrorMessage = error.localizedDescription
            }
        }
    }

    private func configureGlobalPushToTalk(enabled: Bool) {
        do {
            if globalPushToTalkHotKey == nil {
                globalPushToTalkHotKey = try makeGlobalPushToTalkHotKey(
                    shortcut: globalPushToTalkShortcut
                )
            }
            try globalPushToTalkHotKey?.setEnabled(enabled)
            globalPushToTalkError = nil
        } catch {
            isGlobalPushToTalkEnabled = false
            UserDefaults.standard.set(false, forKey: "globalPushToTalkEnabled")
            globalPushToTalkError = error.localizedDescription
        }
    }

    private func makeGlobalPushToTalkHotKey(
        shortcut: GlobalHotKeyShortcut
    ) throws -> GlobalPushToTalkHotKey {
        try GlobalPushToTalkHotKey(shortcut: shortcut, identifierID: 1) { [weak self] pressed in
            guard let self else { return }
            if pressed {
                self.beginTransmission()
            } else {
                self.releasePushToTalk()
            }
        }
    }

    func joinSelectedChannel() {
        guard let selectedChannelID else { return }
        joinChannel(selectedChannelID)
    }

    func joinChannel(_ channelID: MumbleChannel.ID) {
        guard case .connected(let sessionID) = connectionState else { return }
        Task {
            do {
                try await controlConnection.send(
                    MumbleCommands.joinChannel(session: sessionID, channelID: channelID)
                )
            } catch {
                connectionState = .failed(message: L10n.text("channel.joinError", error.localizedDescription))
            }
        }
    }

    func saveChannel(
        _ request: ChannelEditorRequest,
        name: String,
        description: String,
        temporary: Bool,
        position: Int32,
        maximumUsers: UInt32?
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, case .connected = connectionState else { return }
        Task {
            do {
                let frame: MumbleFrame
                if let channel = request.channel {
                    frame = try MumbleCommands.updateChannel(
                        channelID: channel.id,
                        name: trimmedName,
                        description: description,
                        position: position,
                        maximumUsers: maximumUsers
                    )
                } else {
                    frame = try MumbleCommands.createChannel(
                        parentID: request.parentID,
                        name: trimmedName,
                        description: description,
                        temporary: temporary,
                        position: position,
                        maximumUsers: maximumUsers
                    )
                }
                try await controlConnection.send(frame)
            } catch {
                serverManagementError = error.localizedDescription
            }
        }
    }

    func deleteChannel(_ channel: MumbleChannel) {
        pendingChannelDeletion = nil
        guard case .connected = connectionState else { return }
        Task {
            do {
                try await controlConnection.send(MumbleCommands.removeChannel(channelID: channel.id))
            } catch {
                serverManagementError = error.localizedDescription
            }
        }
    }

    func setChannelLink(_ channel: MumbleChannel, target: MumbleChannel, linked: Bool) {
        guard case .connected = connectionState else { return }
        Task {
            do {
                try await controlConnection.send(
                    MumbleCommands.setChannelLink(
                        channelID: channel.id,
                        linkedChannelID: target.id,
                        linked: linked
                    )
                )
            } catch {
                serverManagementError = error.localizedDescription
            }
        }
    }

    func setChannelListening(_ channel: MumbleChannel, listening: Bool) {
        guard case .connected(let sessionID) = connectionState else { return }
        Task {
            do {
                try await controlConnection.send(
                    MumbleCommands.setChannelListening(
                        session: sessionID,
                        channelID: channel.id,
                        listening: listening
                    )
                )
            } catch {
                serverManagementError = error.localizedDescription
            }
        }
    }

    func setListeningVolume(_ volume: Float, for channel: MumbleChannel) {
        guard case .connected(let sessionID) = connectionState else { return }
        Task {
            do {
                try await controlConnection.send(
                    MumbleCommands.setListeningVolume(
                        session: sessionID,
                        channelID: channel.id,
                        adjustment: volume
                    )
                )
            } catch {
                serverManagementError = error.localizedDescription
            }
        }
    }

    func sendChatMessage() {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let selectedChannelID else { return }
        guard text.utf8.count <= (text.contains("<img") ? serverImageMessageLengthLimit : serverMessageLengthLimit) else {
            serverManagementError = L10n.text("chat.tooLong")
            return
        }
        chatDraft = ""
        if chatHistory.last != text { chatHistory.append(text) }
        chatHistoryIndex = nil

        Task {
            do {
                try await controlConnection.send(MumbleCommands.sendText(text, toChannel: selectedChannelID))
                chatEntries.append(
                    ChatEntry(author: L10n.text("chat.you"), timestamp: Date(), text: text, isLocal: true)
                )
                trimChatLog()
            } catch {
                connectionState = .failed(message: L10n.text("chat.sendError", error.localizedDescription))
            }
        }
    }

    func navigateChatHistory(older: Bool) {
        guard !chatHistory.isEmpty else { return }
        let current = chatHistoryIndex ?? chatHistory.count
        let next = older ? max(0, current - 1) : min(chatHistory.count, current + 1)
        chatHistoryIndex = next == chatHistory.count ? nil : next
        chatDraft = next == chatHistory.count ? "" : chatHistory[next]
    }

    func completeChatUsername() {
        let prefix = chatDraft.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        guard !prefix.isEmpty else { return }
        let names = flattenedChannels.flatMap(\.users).map { displayName(for: $0) }
        guard let match = names.sorted().first(where: { $0.lowercased().hasPrefix(prefix.lowercased()) }) else { return }
        chatDraft.removeLast(prefix.count); chatDraft += match + " "
    }

    func pasteImageIntoChat() {
        guard serverAllowsHTML, let image = NSImage(pasteboard: .general),
              let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            serverManagementError = L10n.text("chat.noImage")
            return
        }
        let html = "<img src=\"data:image/png;base64,\(data.base64EncodedString())\">"
        guard html.utf8.count <= serverImageMessageLengthLimit else {
            serverManagementError = L10n.text("chat.imageTooLarge"); return
        }
        chatDraft += html
    }

    func sendPrivateMessage(_ text: String, to user: MumbleUser) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, case .connected = connectionState else { return }
        let recipient = user.name

        Task {
            do {
                try await controlConnection.send(
                    MumbleCommands.sendPrivateText(trimmed, toSession: user.id)
                )
                chatEntries.append(
                    ChatEntry(
                        author: L10n.text("chat.privateTo", recipient),
                        timestamp: Date(),
                        text: trimmed,
                        isLocal: true,
                        isPrivate: true
                    )
                )
                trimChatLog()
            } catch {
                connectionState = .failed(message: L10n.text("chat.sendError", error.localizedDescription))
            }
        }
    }

    func registerUser(_ user: MumbleUser) {
        guard user.registeredUserID == nil, case .connected = connectionState else { return }
        Task {
            do { try await controlConnection.send(MumbleCommands.registerUser(session: user.id)) }
            catch { serverManagementError = error.localizedDescription }
        }
    }

    func displayName(for user: MumbleUser) -> String {
        user.certificateHash.flatMap { localUserNicknames[$0] } ?? user.name
    }

    func isFriend(_ user: MumbleUser) -> Bool {
        user.certificateHash.map(friendCertificateHashes.contains) ?? false
    }

    func toggleFriend(_ user: MumbleUser) {
        guard let hash = user.certificateHash else { return }
        if friendCertificateHashes.remove(hash) == nil { friendCertificateHashes.insert(hash) }
        UserDefaults.standard.set(Array(friendCertificateHashes), forKey: "friendCertificateHashes")
    }

    func isIgnoringMessages(from user: MumbleUser) -> Bool {
        user.certificateHash.map(ignoredMessageUserHashes.contains) ?? false
    }
    func isIgnoringTTS(from user: MumbleUser) -> Bool {
        user.certificateHash.map(ignoredTTSUserHashes.contains) ?? false
    }
    func toggleIgnoreMessages(_ user: MumbleUser) {
        guard let hash = user.certificateHash else { return }
        if ignoredMessageUserHashes.remove(hash) == nil { ignoredMessageUserHashes.insert(hash) }
        UserDefaults.standard.set(Array(ignoredMessageUserHashes), forKey: "ignoredMessageUserHashes")
    }
    func toggleIgnoreTTS(_ user: MumbleUser) {
        guard let hash = user.certificateHash else { return }
        if ignoredTTSUserHashes.remove(hash) == nil { ignoredTTSUserHashes.insert(hash) }
        UserDefaults.standard.set(Array(ignoredTTSUserHashes), forKey: "ignoredTTSUserHashes")
    }
    func setDoubleClickPTTTogglesContinuous(_ enabled: Bool) {
        doubleClickPTTTogglesContinuous = enabled
        UserDefaults.standard.set(enabled, forKey: "doubleClickPTTTogglesContinuous")
    }
    func togglePTTContinuousMode() {
        guard doubleClickPTTTogglesContinuous else { return }
        setTransmissionMode(transmissionMode == .continuous ? .pushToTalk : .continuous)
    }

    func setLocalNickname(_ nickname: String, for user: MumbleUser) {
        guard let hash = user.certificateHash else { return }
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { localUserNicknames.removeValue(forKey: hash) }
        else { localUserNicknames[hash] = trimmed }
        if let data = try? JSONEncoder().encode(localUserNicknames) {
            UserDefaults.standard.set(data, forKey: "localUserNicknames")
        }
    }

    func requestUserResources(_ user: MumbleUser) {
        guard (user.hasCommentResource && user.commentText.isEmpty) || (user.hasAvatarResource && user.avatarData == nil),
              requestedUserResourceSessions.insert(user.id).inserted,
              case .connected = connectionState else { return }
        Task {
            do {
                try await controlConnection.send(MumbleCommands.requestUserResources(
                    session: user.id,
                    comment: user.hasCommentResource && user.commentText.isEmpty,
                    texture: user.hasAvatarResource && user.avatarData == nil
                ))
            } catch { requestedUserResourceSessions.remove(user.id) }
        }
    }

    func updateOwnProfile(comment: String, avatarData: Data?) {
        guard case .connected(let session) = connectionState else { return }
        Task {
            do {
                try await controlConnection.send(MumbleCommands.setUserComment(session: session, comment: comment))
                if let avatarData { try await controlConnection.send(MumbleCommands.setUserTexture(session: session, texture: avatarData)) }
            } catch { serverManagementError = error.localizedDescription }
        }
    }

    func setPrioritySpeaker(_ enabled: Bool, for user: MumbleUser) {
        guard case .connected = connectionState else { return }
        Task {
            do { try await controlConnection.send(MumbleCommands.setPrioritySpeaker(session: user.id, enabled: enabled)) }
            catch { serverManagementError = error.localizedDescription }
        }
    }

    func setServerMuted(_ muted: Bool, for user: MumbleUser) {
        sendServerAudioState(user, muted: muted, deafened: nil)
    }

    func setServerDeafened(_ deafened: Bool, for user: MumbleUser) {
        sendServerAudioState(user, muted: deafened ? true : nil, deafened: deafened)
    }

    private func sendServerAudioState(_ user: MumbleUser, muted: Bool?, deafened: Bool?) {
        guard case .connected = connectionState else { return }
        Task {
            do { try await controlConnection.send(MumbleCommands.setServerAudioState(session: user.id, muted: muted, deafened: deafened)) }
            catch { serverManagementError = error.localizedDescription }
        }
    }

    func performModeration(
        _ request: UserModerationRequest,
        reason: String,
        banCertificate: Bool,
        banIP: Bool
    ) {
        guard case .connected = connectionState else { return }
        Task {
            do {
                try await controlConnection.send(MumbleCommands.removeUser(
                    session: request.user.id,
                    reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                    ban: request.action == .ban,
                    banCertificate: banCertificate,
                    banIP: banIP
                ))
            } catch { serverManagementError = error.localizedDescription }
        }
    }

    func requestACL(for channel: MumbleChannel) {
        aclConfiguration = nil; isLoadingACL = true
        Task { do { try await controlConnection.send(MumbleCommands.requestACL(channelID: channel.id)) }
            catch { isLoadingACL = false; serverManagementError = error.localizedDescription } }
    }

    func saveACL(_ configuration: MumbleACLConfiguration) {
        Task { do { try await controlConnection.send(MumbleCommands.setACL(configuration)); aclConfiguration = configuration }
            catch { serverManagementError = error.localizedDescription } }
    }

    func requestRegisteredUsers() {
        isLoadingRegisteredUsers = true
        Task { do { try await controlConnection.send(MumbleCommands.requestRegisteredUsers()) }
            catch { isLoadingRegisteredUsers = false; serverManagementError = error.localizedDescription } }
    }

    func removeRegisteredUser(_ user: MumbleRegisteredUser) {
        Task { do { try await controlConnection.send(MumbleCommands.updateRegisteredUser(id: user.id, name: "")) }
            catch { serverManagementError = error.localizedDescription } }
    }

    func renameRegisteredUser(_ user: MumbleRegisteredUser, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { do { try await controlConnection.send(MumbleCommands.updateRegisteredUser(id: user.id, name: trimmed)) }
            catch { serverManagementError = error.localizedDescription } }
    }

    func showUserInformation(_ user: MumbleUser) {
        guard case .connected = connectionState else { return }
        userInformationTarget = user
        userStatistics = nil
        isLoadingUserStatistics = true
        requestUserStatistics(sessionID: user.id)
    }

    func refreshUserInformation() {
        guard let userInformationTarget, case .connected = connectionState else { return }
        requestUserStatistics(sessionID: userInformationTarget.id)
    }

    func closeUserInformation() {
        userInformationTarget = nil
        userStatistics = nil
        isLoadingUserStatistics = false
    }

    func currentUser(sessionID: UInt32) -> MumbleUser? {
        findUser(session: sessionID, in: channels)
    }

    private func requestUserStatistics(sessionID: UInt32) {
        Task {
            do {
                try await controlConnection.send(
                    MumbleCommands.requestUserStatistics(session: sessionID)
                )
            } catch {
                if userStatistics == nil { isLoadingUserStatistics = false }
            }
        }
    }

    /// Returns to the channel the local user was in before the current one.
    func returnToPreviousChannel() {
        guard case .connected(let sessionID) = connectionState,
              let previousChannelID = channelHistory.previousChannelID else { return }
        Task {
            do {
                try await controlConnection.send(
                    MumbleCommands.joinChannel(session: sessionID, channelID: previousChannelID)
                )
            } catch {
                connectionState = .failed(
                    message: L10n.text("channel.joinError", error.localizedDescription)
                )
            }
        }
    }

    var canReturnToPreviousChannel: Bool {
        guard case .connected = connectionState else { return false }
        return channelHistory.previousChannelID != nil
    }

    private func trackOwnChannel(_ channelID: MumbleChannel.ID) {
        _ = channelHistory.observe(channelID: channelID)
        selectedChannelID = channelID
        expandChannelPath(to: channelID)
    }

    private func expandChannelPath(to channelID: MumbleChannel.ID) {
        var current = flattenedChannels.first { $0.id == channelID }
        while let channel = current {
            expandedChannelIDs.insert(channel.id)
            current = channel.parentID.flatMap { parentID in
                flattenedChannels.first { $0.id == parentID }
            }
        }
    }

    private func handle(_ frame: MumbleFrame) {
        do {
            if frame.type == .userState,
               case .connected(let ownSession) = connectionState {
                let state = try frame.decode(as: MumbleProto_UserState.self)
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
                try handleIncomingAudio(frame)
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
                chatEntries.append(
                    ChatEntry(
                        author: author,
                        timestamp: Date(),
                        text: message.message,
                        isLocal: false,
                        isPrivate: isPrivate
                    )
                )
                trimChatLog()
                if notificationsEnabled, isPrivate {
                    MumbleNotificationService.post(
                        title: L10n.text("notifications.private.title", baseAuthor),
                        body: MessageText.plainText(from: message.message)
                    )
                }
                if textToSpeechEnabled, actorUser.map({ !isIgnoringTTS(from: $0) }) ?? true {
                    messageSpeechService.speak(
                        L10n.text("tts.message", baseAuthor, MessageText.plainText(from: message.message))
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
            if (notificationsEnabled || audioCuesEnabled), didSynchronize {
                notifyUserChanges(from: channelSnapshot, to: snapshot.channels, ownSession: snapshot.session)
            }
            channelSnapshot = snapshot.channels
            rebuildChannels()
            if case .synchronized = change { applyChannelExpansionPolicy() }
            serverWelcomeText = snapshot.welcomeText
            if let ownSession = snapshot.session {
                let ownUser = findUser(session: ownSession, in: snapshot.channels)
                let recognizedHash = ownUser?.certificateHash
                if recognizedHash != serverRecognizedIdentityHash, let recognizedHash {
                    identityLogger.notice("Murmur recognized client certificate hash: \(recognizedHash, privacy: .public)")
                }
                serverRecognizedIdentityHash = recognizedHash
                if let ownUser {
                    applyServerSelfState(ownUser)
                    trackOwnChannel(ownUser.channelID)
                }
            }
            if selectedChannelID == nil {
                selectedChannelID = snapshot.channels.first?.id
            }
            if case .synchronized(let session) = change {
                connectionState = .connected(session: session)
                let wasReconnecting = isReconnecting
                didSynchronize = true
                reconnectPolicy.reset()
                isReconnecting = false
                reconnectAttempt = 0
                if notificationsEnabled {
                    MumbleNotificationService.post(
                        title: L10n.text(wasReconnecting ? "notifications.reconnected.title" : "notifications.connected.title"),
                        body: selectedServer?.name ?? "Mumble"
                    )
                }
                if audioCuesEnabled { audioCueService.play(.connected) }
                reportSelfAudioState(session: session)
                if wasReconnecting, let selectedChannelID {
                    Task {
                        try? await controlConnection.send(
                            MumbleCommands.joinChannel(session: session, channelID: selectedChannelID)
                        )
                    }
                }
                refreshAutomaticAudioCapture()
                joinPendingChannelPath()
            }
        } catch {
            connectionState = .failed(message: L10n.text("protocol.error", error.localizedDescription))
        }
    }

    private func handleIncomingAudio(_ frame: MumbleFrame) throws {
        let incoming = try MumbleVoicePacket.decodeTunneledAudio(frame)
        audioPacketsReceived += 1
        let pipeline: AudioReceivePipeline
        if let existing = audioReceivePipelines[incoming.senderSession] {
            pipeline = existing
        } else {
            pipeline = try AudioReceivePipeline(targetDelayFrames: jitterBufferDelayFrames)
            audioReceivePipelines[incoming.senderSession] = pipeline
            audioMixer.register(source: incoming.senderSession)
            seedMixerSettings(session: incoming.senderSession)
            startAudioMixLoop()
            startAudioDrain(session: incoming.senderSession, pipeline: pipeline)
        }

        pipeline.push(
            frameNumber: incoming.frameNumber,
            packet: BufferedAudioPacket(
                opusData: incoming.opusData,
                volume: incoming.volumeAdjustment,
                isTerminator: incoming.isTerminator
            )
        )

        updateTalking(session: incoming.senderSession, isTerminator: incoming.isTerminator)
    }

    private func updateTalking(session: UInt32, isTerminator: Bool) {
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
        if changed { rebuildChannels() }
    }

    private func startTalkingPruneLoop() {
        guard talkingPruneTask == nil else { return }
        talkingPruneTask = Task {
            defer { talkingPruneTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                if talkingTracker.pruneExpired(now: ProcessInfo.processInfo.systemUptime) {
                    rebuildChannels()
                }
                if talkingTracker.talkingSessions.isEmpty { return }
            }
        }
    }

    /// Re-applies the live talking overlay onto the last protocol snapshot.
    private func rebuildChannels() {
        var talking = talkingTracker.talkingSessions
        if isTransmitting, case .connected(let ownSession) = connectionState {
            talking.insert(ownSession)
        }
        channels = Self.applyTalking(to: channelSnapshot, talking: talking)
    }

    private static func applyTalking(
        to channels: [MumbleChannel],
        talking: Set<UInt32>
    ) -> [MumbleChannel] {
        channels.map { channel in
            var channel = channel
            channel.users = channel.users.map { user in
                var user = user
                user.isTalking = talking.contains(user.id)
                return user
            }
            channel.children = applyTalking(to: channel.children, talking: talking)
            return channel
        }
    }

    private func startAudioDrain(session: UInt32, pipeline: AudioReceivePipeline) {
        audioDrainTasks[session]?.cancel()
        audioDrainTasks[session] = Task {
            defer {
                audioReceivePipelines.removeValue(forKey: session)
                audioDrainTasks.removeValue(forKey: session)
                audioMixer.unregister(source: session)
                if talkingTracker.clear(session: session) { rebuildChannels() }
            }
            var waitingReads = 0
            while !Task.isCancelled {
                do {
                    switch try pipeline.read() {
                    case .waiting:
                        waitingReads += 1
                        if waitingReads > 100 { return }
                        try await Task.sleep(for: .milliseconds(2))
                    case .samples(let samples):
                        waitingReads = 0
                        audioMixer.push(source: session, samples: samples)
                    case .finished:
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    audioErrorMessage = error.localizedDescription
                    return
                }
            }
        }
    }

    private func startAudioMixLoop() {
        guard audioMixTask == nil else { return }
        audioMixTask = Task {
            defer { audioMixTask = nil }
            while !Task.isCancelled {
                do {
                    switch audioMixer.read() {
                    case .inactive:
                        audioPlayback?.stop()
                        audioPlayback = nil
                        return
                    case .waiting:
                        try await Task.sleep(for: .milliseconds(2))
                    case .samples(let samples):
                        if echoCancellationEnabled { echoCanceller.updateReference(samples) }
                        if !isDeafened { try playIncomingSamples(samples) }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    audioErrorMessage = error.localizedDescription
                    return
                }
            }
        }
    }

    private func playIncomingSamples(_ samples: [Float]) throws {
        let playback: AudioPlaybackService
        if let existing = audioPlayback {
            playback = existing
        } else {
            playback = try AudioPlaybackService()
            try playback.selectDevice(selectedOutputDeviceID)
            try playback.start()
            audioPlayback = playback
        }
        try playback.enqueue(samples: samples)
    }

    private func handleCryptSetup(_ frame: MumbleFrame) throws {
        let setup = try frame.decode(as: MumbleProto_CryptSetup.self)
        if setup.hasKey, setup.hasClientNonce, setup.hasServerNonce {
            let state = try MumbleCryptState(
                key: setup.key,
                clientNonce: setup.clientNonce,
                serverNonce: setup.serverNonce
            )
            if let server = selectedServer {
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

    private func startUDP(host: String, port: UInt16, cryptState: MumbleCryptState) {
        guard proxyType == .none else {
            isUsingUDP = false
            Task { await voiceRouter.configureUDP(nil) }
            return
        }
        stopUDP()
        let udpConnection = MumbleUDPConnection(cryptState: cryptState)
        self.udpConnection = udpConnection
        Task { await voiceRouter.configureUDP(udpConnection) }

        udpTask = Task {
            let events = await udpConnection.connect(host: host, port: port)
            for await event in events {
                guard !Task.isCancelled else { return }
                switch event {
                case .ready:
                    startUDPPingLoop(udpConnection)
                case .packet(let packet):
                    if (try? MumbleUDPPacket.pingTimestamp(
                        from: packet,
                        protocolVersion: serverProtocolVersion
                    )) != nil {
                        lastUDPResponseAt = Date()
                        isUsingUDP = true
                        await voiceRouter.setUDPAvailable(true)
                    } else {
                        lastUDPResponseAt = Date()
                        isUsingUDP = true
                        await voiceRouter.setUDPAvailable(true)
                        do {
                            try handleIncomingAudio(MumbleFrame(type: .udpTunnel, payload: packet))
                        } catch {
                            audioErrorMessage = error.localizedDescription
                        }
                    }
                case .failed:
                    isUsingUDP = false
                    await voiceRouter.setUDPAvailable(false)
                case .disconnected:
                    isUsingUDP = false
                    await voiceRouter.setUDPAvailable(false)
                }
            }
        }
    }

    private func startUDPPingLoop(_ udpConnection: MumbleUDPConnection) {
        guard proxyType == .none else { return }
        udpPingTask?.cancel()
        udpPingTask = Task {
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
                        await voiceRouter.setUDPAvailable(false)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    isUsingUDP = false
                    await voiceRouter.setUDPAvailable(false)
                    return
                }
            }
        }
    }

    private func stopUDP() {
        udpTask?.cancel()
        udpTask = nil
        udpPingTask?.cancel()
        udpPingTask = nil
        isUsingUDP = false
        lastUDPResponseAt = nil
        cryptState = nil
        if let udpConnection {
            Task { await udpConnection.disconnect() }
        }
        udpConnection = nil
        Task { await voiceRouter.configureUDP(nil) }
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

    private func saveDeviceSelection(_ deviceID: UInt32?, key: String) {
        if let deviceID { UserDefaults.standard.set(NSNumber(value: deviceID), forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(controlPingIntervalSeconds))
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

    private func findChannel(id: UInt32, in channels: [MumbleChannel]) -> MumbleChannel? {
        for channel in channels {
            if channel.id == id { return channel }
            if let match = findChannel(id: id, in: channel.children) { return match }
        }
        return nil
    }

    func contextActions(for context: UInt32) -> [ServerContextAction] {
        serverContextActions.filter { $0.contexts & context != 0 }
    }

    func performContextAction(_ action: ServerContextAction, user: MumbleUser? = nil, channel: MumbleChannel? = nil) {
        Task { do { try await controlConnection.send(MumbleCommands.performContextAction(
            action.action, session: user?.id, channelID: channel?.id
        )) } catch { serverManagementError = error.localizedDescription } }
    }

    private func flattenChannels(_ channels: [MumbleChannel]) -> [MumbleChannel] {
        channels.flatMap { [$0] + flattenChannels($0.children) }
    }

    private func userName(session: UInt32) -> String {
        findUser(session: session, in: channels)?.name ?? L10n.text("user.unknown", session)
    }

    private func notifyUserChanges(
        from oldChannels: [MumbleChannel],
        to newChannels: [MumbleChannel],
        ownSession: UInt32?
    ) {
        let oldUsers = Dictionary(uniqueKeysWithValues: allUsers(in: oldChannels).map { ($0.id, $0) })
        let newUsers = Dictionary(uniqueKeysWithValues: allUsers(in: newChannels).map { ($0.id, $0) })
        for user in newUsers.values where oldUsers[user.id] == nil && user.id != ownSession {
            if notificationsEnabled { MumbleNotificationService.post(title: L10n.text("notifications.userJoined.title"), body: user.name) }
            if audioCuesEnabled { audioCueService.play(.userJoined) }
        }
        for user in oldUsers.values where newUsers[user.id] == nil && user.id != ownSession {
            if notificationsEnabled { MumbleNotificationService.post(title: L10n.text("notifications.userLeft.title"), body: user.name) }
            if audioCuesEnabled { audioCueService.play(.userLeft) }
        }
    }

    func setChatLogLimit(_ limit: Int) {
        chatLogLimit = min(5_000, max(50, limit)); UserDefaults.standard.set(chatLogLimit, forKey: "chatLogLimit")
        trimChatLog()
    }
    func setChatUses24HourTime(_ enabled: Bool) {
        chatUses24HourTime = enabled; UserDefaults.standard.set(enabled, forKey: "chatUses24HourTime")
    }
    func formattedChatTime(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = .current
        formatter.dateFormat = chatUses24HourTime ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
    private func trimChatLog() {
        if chatEntries.count > chatLogLimit { chatEntries.removeFirst(chatEntries.count - chatLogLimit) }
    }

    private func allUsers(in channels: [MumbleChannel]) -> [MumbleUser] {
        channels.flatMap { $0.users + allUsers(in: $0.children) }
    }

    private func findUser(session: UInt32, in channels: [MumbleChannel]) -> MumbleUser? {
        for channel in channels {
            if let user = channel.users.first(where: { $0.id == session }) { return user }
            if let user = findUser(session: session, in: channel.children) { return user }
        }
        return nil
    }

    static let preview: SessionStore = {
        let loungeUsers = [
            MumbleUser(id: 1, name: "Leo", channelID: 1, isTalking: true),
            MumbleUser(id: 2, name: "Mina", channelID: 1),
            MumbleUser(id: 3, name: "Alex", channelID: 1, isSelfMuted: true)
        ]
        let projectUsers = [
            MumbleUser(id: 4, name: "Sam", channelID: 2),
            MumbleUser(id: 5, name: "Riley", channelID: 2)
        ]
        let channels = [
            MumbleChannel(
                id: 0,
                name: "Root",
                children: [
                    MumbleChannel(id: 1, parentID: 0, name: "Lounge", users: loungeUsers),
                    MumbleChannel(id: 2, parentID: 0, name: "Project Room", users: projectUsers),
                    MumbleChannel(id: 3, parentID: 0, name: "Quiet Corner")
                ]
            )
        ]
        return SessionStore(
            servers: [
                MumbleServer(name: "Community", host: "voice.example.net", username: "Leo", isFavorite: true),
                MumbleServer(name: "Local Server", host: "localhost", username: "Leo")
            ],
            channels: channels,
            connectionState: .connected(session: 1)
        )
    }()
}

actor MumbleVoiceRouter {
    private let controlConnection: MumbleControlConnection
    private var udpConnection: MumbleUDPConnection?
    private var udpAvailable = false
    private var pendingSends: [(Data, CheckedContinuation<Void, Error>)] = []
    private var isDrainingSends = false

    init(controlConnection: MumbleControlConnection) {
        self.controlConnection = controlConnection
    }

    func configureUDP(_ connection: MumbleUDPConnection?) {
        udpConnection = connection
        if connection == nil { udpAvailable = false }
    }

    func setUDPAvailable(_ available: Bool) {
        udpAvailable = available
    }

    func send(_ packet: Data) async throws {
        try await withCheckedThrowingContinuation { continuation in
            pendingSends.append((packet, continuation))
            guard !isDrainingSends else { return }
            isDrainingSends = true
            Task { await drainSends() }
        }
    }

    private func drainSends() async {
        while !pendingSends.isEmpty {
            let (packet, continuation) = pendingSends.removeFirst()
            do {
                try await sendImmediately(packet)
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        isDrainingSends = false
    }

    private func sendImmediately(_ packet: Data) async throws {
        if udpAvailable, let udpConnection {
            do {
                try await udpConnection.send(packet)
                return
            } catch {
                udpAvailable = false
            }
        }
        try await controlConnection.send(MumbleFrame(type: .udpTunnel, payload: packet))
    }
}
