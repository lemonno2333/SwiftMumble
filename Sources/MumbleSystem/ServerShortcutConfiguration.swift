import Foundation

public enum GlobalAudioShortcutAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case toggleMute, toggleDeafen, volumeDown, volumeUp, cycleTransmissionMode

    public var id: String { rawValue }

    public var hotKeyID: UInt32 {
        switch self {
        case .toggleMute: 10
        case .toggleDeafen: 11
        case .volumeDown: 12
        case .volumeUp: 13
        case .cycleTransmissionMode: 14
        }
    }
}

public struct ServerShortcutConfiguration: Codable, Equatable, Sendable {
    public var pushToTalk: GlobalHotKeyShortcut
    public var pushToMute: GlobalHotKeyShortcut
    public var audio: [GlobalAudioShortcutAction: GlobalHotKeyShortcut]
    public var whisper: GlobalHotKeyShortcut

    public init(
        pushToTalk: GlobalHotKeyShortcut,
        pushToMute: GlobalHotKeyShortcut,
        audio: [GlobalAudioShortcutAction: GlobalHotKeyShortcut],
        whisper: GlobalHotKeyShortcut
    ) {
        self.pushToTalk = pushToTalk
        self.pushToMute = pushToMute
        self.audio = audio
        self.whisper = whisper
    }
}

public struct ServerShortcutProfiles: Codable, Equatable, Sendable {
    public var global: ServerShortcutConfiguration
    public private(set) var overrides: [String: ServerShortcutConfiguration]

    public init(global: ServerShortcutConfiguration, overrides: [String: ServerShortcutConfiguration] = [:]) {
        self.global = global
        self.overrides = overrides
    }

    public func configuration(serverID: UUID?) -> ServerShortcutConfiguration {
        guard let serverID else { return global }
        return overrides[serverID.uuidString] ?? global
    }

    public mutating func setOverride(_ configuration: ServerShortcutConfiguration?, serverID: UUID) {
        overrides[serverID.uuidString] = configuration
    }
}
