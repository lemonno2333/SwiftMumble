import Foundation
import AppKit
import MumbleAudio
import MumbleProtocol
import MumbleSystem
import Observation
import OSLog

let identityLogger = Logger(subsystem: "com.leo.SwiftMumble", category: "ClientIdentity")
private let audioDiagnosticsStarted: Void = { AudioDiagnostics.shared.beginSession() }()

struct PendingServerCertificate: Identifiable, Equatable {
    let id = UUID()
    var serverID: MumbleServer.ID
    var host: String
    var subject: String
    var fingerprint: MumbleCertificateFingerprint
    var previousFingerprint: MumbleCertificateFingerprint?
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
    var servers: [MumbleServer] { serverRepository.servers }
    var selectedServerID: MumbleServer.ID? { serverRepository.selectedID }
    var activeServerID: MumbleServer.ID? { serverRepository.activeID }
    var selectedChannelID: MumbleChannel.ID?
    var channels: [MumbleChannel]
    var connectionState: ConnectionState
    var isShowingServerSheet = false
    var editingServerID: MumbleServer.ID?
    var pendingServerDeletion: MumbleServer?
    var serverManagementError: String?
    var serverWelcomeText = ""
    var currentPermissions: MumblePermission = []
    var pendingServerCertificate: PendingServerCertificate?
    var isUsingUDP = false
    var clientIdentityInfo: ClientIdentityInfo?
    var clientIdentityError: String?
    var serverRecognizedIdentityHash: String?
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
    var isShowingServerInformation = false
    var lastControlPingMilliseconds: Double?
    @ObservationIgnored var lastControlPongAt: Date?
    var serverMaximumUsers: UInt32?
    var serverMaximumBandwidth: UInt32?
    var serverRecordingAllowed = false
    var channelExpansionPolicy: ChannelExpansionPolicy = .currentPath
    var showsReturnToPreviousChannelControl = false
    var showsHideEmptyChannelsControl = false
    var expandedChannelIDs: Set<UInt32> = []
    var userInformationTarget: MumbleUser?
    var userStatistics: MumbleUserStatistics?
    var isLoadingUserStatistics = false
    var notificationsEnabled = false
    var touchBarControlStripEnabled = false
    var textToSpeechEnabled = false
    var channelEditorRequest: ChannelEditorRequest?
    var pendingChannelDeletion: MumbleChannel?
    var listeningChannelIDs: Set<UInt32> = []
    var listeningChannelVolumes: [UInt32: Float] = [:]
    /// Live speaking set, observed separately from the channel tree so a talk
    /// edge only invalidates the rows that render it — not the whole tree.
    var talkingSessions: Set<UInt32> = []
    var hideEmptyChannels = false
    var hiddenChannelIDs: Set<UInt32> = []
    var pinnedChannelIDs: Set<UInt32> = []
    var discoveredServers: [DiscoveredMumbleServer] = []

    @ObservationIgnored let chat = ChatStore()
    @ObservationIgnored let shortcuts = ShortcutController()
    @ObservationIgnored let serverRepository: ServerRepository
    @ObservationIgnored let connectionCoordinator = ConnectionCoordinator()
    @ObservationIgnored let audioSession = AudioSessionController(
        voiceProcessingEnabled: UserDefaults.standard.bool(forKey: "voiceProcessingEnabled")
    )
    @ObservationIgnored let controlConnection: MumbleControlConnection
    @ObservationIgnored let voiceRouter: MumbleVoiceRouter
    @ObservationIgnored var protocolState = MumbleServerState()
    @ObservationIgnored var channelSnapshot: [MumbleChannel] = []
    @ObservationIgnored var channelHistory = MumbleChannelHistory()
    @ObservationIgnored let messageSpeechService = MessageSpeechService()
    @ObservationIgnored var serverProtocolVersion = MumbleProtocolVersion(major: 1, minor: 4, patch: 0)
    @ObservationIgnored var cryptState: MumbleCryptState?
    @ObservationIgnored var udpConnection: MumbleUDPConnection?
    @ObservationIgnored var udpTask: Task<Void, Never>?
    @ObservationIgnored var udpPingTask: Task<Void, Never>?
    @ObservationIgnored var lastUDPResponseAt: Date?
    @ObservationIgnored var lastCryptResyncRequestAt: Date?
    @ObservationIgnored let cryptResyncPolicy = MumbleCryptResyncPolicy()
    /// Serial queue that parses TCP-tunneled voice off the MainActor while
    /// preserving packet order.
    @ObservationIgnored let tunnelAudioQueue = DispatchQueue(
        label: "com.leo.SwiftMumble.tunnelAudio",
        qos: .userInitiated
    )
    @ObservationIgnored var clientIdentity: MumbleTLSClientIdentity?
    @ObservationIgnored var muteStateBeforePushToMute = false
    @ObservationIgnored var activeVoiceTargetID: UInt32 = 0
    @ObservationIgnored var isWhisperPressed = false
    @ObservationIgnored var requestedUserResourceSessions: Set<UInt32> = []
    @ObservationIgnored var pendingChannelPath: [String] = []
    @ObservationIgnored var requestedChannelDescriptions: Set<UInt32> = []
    @ObservationIgnored var lanDiscovery: LANMumbleDiscovery?

    init(
        servers: [MumbleServer]? = nil,
        channels: [MumbleChannel] = [],
        connectionState: ConnectionState = .disconnected,
        activeServerID: MumbleServer.ID? = nil,
        performStartup: Bool = true
    ) {
        _ = audioDiagnosticsStarted
        let controlConnection = MumbleControlConnection()
        self.controlConnection = controlConnection
        voiceRouter = MumbleVoiceRouter(controlConnection: controlConnection)
        let resolvedServers = servers ?? SavedServerStore.load()
        serverRepository = ServerRepository(
            servers: resolvedServers,
            selectedID: activeServerID ?? resolvedServers.first?.id,
            activeID: activeServerID
        )
        self.channels = channels
        self.connectionState = connectionState
        selectedChannelID = channels.first?.id
        let defaults = UserDefaults.standard
        let inputID = defaults.object(forKey: "selectedInputDeviceID") as? NSNumber
        let outputID = defaults.object(forKey: "selectedOutputDeviceID") as? NSNumber
        selectedInputDeviceID = inputID.map { UInt32(truncating: $0) }
        selectedOutputDeviceID = outputID.map { UInt32(truncating: $0) }
        if performStartup { loadClientIdentity() }
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
        unmuteOnUndeafen = defaults.object(forKey: "unmuteOnUndeafen") as? Bool ?? true
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        touchBarControlStripEnabled = defaults.bool(forKey: "touchBarControlStripEnabled")
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
        channelExpansionPolicy = ChannelExpansionPolicy(rawValue: defaults.string(forKey: "channelExpansionPolicy") ?? "") ?? .currentPath
        showsReturnToPreviousChannelControl = defaults.bool(forKey: "showsReturnToPreviousChannelControl")
        showsHideEmptyChannelsControl = defaults.bool(forKey: "showsHideEmptyChannelsControl")
        audioCuesEnabled = defaults.bool(forKey: "audioCuesEnabled")
        hideEmptyChannels = defaults.bool(forKey: "hideEmptyChannels")
        if !showsHideEmptyChannelsControl { hideEmptyChannels = false }
        bindShortcutHandlers()
        applyShortcutConfigurationForSelectedServer(rebind: false)
        loadChannelPreferences()
        audioMixer.setMasterGain(masterOutputVolume)
        audioMixer.setDuckingGain(duckingVolume)
        inputProcessor.configure(
            echo: echoCancellationEnabled,
            noiseSuppression: noiseSuppressionEnabled,
            automaticGain: automaticGainControlEnabled
        )
        configureRealtimeVoiceActivity()
        if performStartup {
            shortcuts.start()
            lanDiscovery = LANMumbleDiscovery { [weak self] servers in
                Task { @MainActor in self?.discoveredServers = servers }
            }
            lanDiscovery?.start()
            if publicServerDirectoryEnabled { refreshPublicServers() }
        }
    }
}
