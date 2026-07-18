import AppKit
import Foundation
import MumbleSystem
import Observation

@MainActor
@Observable
final class ShortcutController {
    struct Handlers {
        var pushToTalk: (Bool) -> Void
        var pushToMute: (Bool) -> Void
        var audioAction: (GlobalAudioShortcutAction) -> Void
        var whisper: (Bool) -> Void
        var idleAction: (IdleAudioAction) -> Void
    }

    private(set) var isPushToTalkEnabled: Bool
    private(set) var errorMessage: String?
    private(set) var pushToTalkShortcut: GlobalHotKeyShortcut
    private(set) var pushToMuteShortcut: GlobalHotKeyShortcut
    private(set) var isPushToMuteEnabled: Bool
    private(set) var areAudioShortcutsEnabled: Bool
    private(set) var audioShortcuts: [GlobalAudioShortcutAction: GlobalHotKeyShortcut]
    private(set) var idleAction: IdleAudioAction
    private(set) var idleTimeoutMinutes: Int
    private(set) var voiceTarget: ConfiguredVoiceTarget?
    private(set) var whisperShortcut: GlobalHotKeyShortcut
    private(set) var isWhisperEnabled: Bool
    private(set) var serverOverrides: [String: ServerShortcutConfiguration]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var handlers: Handlers?
    @ObservationIgnored private var pushToTalkHotKey: GlobalPushToTalkHotKey?
    @ObservationIgnored private var pushToMuteHotKey: GlobalPushToTalkHotKey?
    @ObservationIgnored private var audioHotKeys: [GlobalAudioShortcutAction: GlobalPushToTalkHotKey] = [:]
    @ObservationIgnored private var whisperHotKey: GlobalPushToTalkHotKey?
    @ObservationIgnored private var idleMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var didPerformIdleAction = false
    @ObservationIgnored private var globalConfiguration: ServerShortcutConfiguration?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPushToTalkEnabled = defaults.bool(forKey: "globalPushToTalkEnabled")
        isPushToMuteEnabled = defaults.bool(forKey: "pushToMuteEnabled")
        areAudioShortcutsEnabled = defaults.bool(forKey: "globalAudioShortcutsEnabled")
        isWhisperEnabled = defaults.bool(forKey: "whisperShortcutEnabled")
        idleAction = IdleAudioAction(rawValue: defaults.string(forKey: "idleAudioAction") ?? "") ?? .none
        idleTimeoutMinutes = min(240, max(1, defaults.object(forKey: "idleTimeoutMinutes") as? Int ?? 10))

        pushToTalkShortcut = Self.decode(
            GlobalHotKeyShortcut.self,
            key: "globalPushToTalkShortcut",
            defaults: defaults
        ) ?? .default
        pushToMuteShortcut = Self.decode(
            GlobalHotKeyShortcut.self,
            key: "pushToMuteShortcut",
            defaults: defaults
        ) ?? GlobalHotKeyShortcut(keyCode: 46, keyLabel: "M", option: true, control: true)
        whisperShortcut = Self.decode(
            GlobalHotKeyShortcut.self,
            key: "whisperShortcut",
            defaults: defaults
        ) ?? GlobalHotKeyShortcut(keyCode: 13, keyLabel: "W", option: true, control: true)

        let defaultAudio: [GlobalAudioShortcutAction: GlobalHotKeyShortcut] = [
            .toggleMute: GlobalHotKeyShortcut(keyCode: 46, keyLabel: "M", command: true, shift: true),
            .toggleDeafen: GlobalHotKeyShortcut(keyCode: 2, keyLabel: "D", command: true, shift: true),
            .volumeDown: GlobalHotKeyShortcut(keyCode: 27, keyLabel: "-", option: true, control: true),
            .volumeUp: GlobalHotKeyShortcut(keyCode: 24, keyLabel: "+", option: true, control: true),
            .cycleTransmissionMode: GlobalHotKeyShortcut(keyCode: 17, keyLabel: "T", option: true, control: true)
        ]
        var resolvedAudio = defaultAudio
        if let saved = Self.decode(
            [GlobalAudioShortcutAction: GlobalHotKeyShortcut].self,
            key: "globalAudioShortcuts",
            defaults: defaults
        ) {
            resolvedAudio.merge(saved) { _, saved in saved }
        }
        audioShortcuts = resolvedAudio
        voiceTarget = Self.decode(ConfiguredVoiceTarget.self, key: "configuredVoiceTarget", defaults: defaults)
        serverOverrides = Self.decode(
            [String: ServerShortcutConfiguration].self,
            key: "serverShortcutOverrides",
            defaults: defaults
        ) ?? [:]
        globalConfiguration = ServerShortcutConfiguration(
            pushToTalk: pushToTalkShortcut,
            pushToMute: pushToMuteShortcut,
            audio: resolvedAudio,
            whisper: whisperShortcut
        )
    }

    func bind(_ handlers: Handlers) {
        self.handlers = handlers
    }

    func start() {
        if isPushToTalkEnabled { configurePushToTalk(enabled: true) }
        if isPushToMuteEnabled { configurePushToMute(enabled: true) }
        if areAudioShortcutsEnabled { configureAudioShortcuts(enabled: true) }
        if isWhisperEnabled { configureWhisper(enabled: true) }
        startIdleMonitor()
    }

    func usesOverride(for serverID: UUID?) -> Bool {
        serverID.map { serverOverrides[$0.uuidString] != nil } ?? false
    }

    func setOverrideEnabled(_ enabled: Bool, for serverID: UUID?) {
        guard let key = serverID?.uuidString else { return }
        if enabled {
            serverOverrides[key] = currentConfiguration
        } else {
            serverOverrides.removeValue(forKey: key)
        }
        persistOverrides()
        applyConfiguration(for: serverID)
    }

    func applyConfiguration(for serverID: UUID?, rebind: Bool = true) {
        let configuration = serverID.flatMap { serverOverrides[$0.uuidString] }
            ?? globalConfiguration
            ?? currentConfiguration
        pushToTalkShortcut = configuration.pushToTalk
        pushToMuteShortcut = configuration.pushToMute
        audioShortcuts = configuration.audio
        whisperShortcut = configuration.whisper
        guard rebind else { return }
        do {
            try pushToTalkHotKey?.setShortcut(configuration.pushToTalk)
            try pushToMuteHotKey?.setShortcut(configuration.pushToMute)
            for action in GlobalAudioShortcutAction.allCases {
                if let shortcut = configuration.audio[action] {
                    try audioHotKeys[action]?.setShortcut(shortcut)
                }
            }
            try whisperHotKey?.setShortcut(configuration.whisper)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPushToTalkEnabled(_ enabled: Bool) {
        configurePushToTalk(enabled: enabled)
        guard errorMessage == nil else { return }
        isPushToTalkEnabled = enabled
        defaults.set(enabled, forKey: "globalPushToTalkEnabled")
    }

    func setPushToTalkShortcut(_ shortcut: GlobalHotKeyShortcut, serverID: UUID?) {
        do {
            if pushToTalkHotKey == nil {
                pushToTalkHotKey = try makeHotKey(shortcut: shortcut, identifier: 1) { [weak self] in
                    self?.handlers?.pushToTalk($0)
                }
            } else {
                try pushToTalkHotKey?.setShortcut(shortcut)
            }
            pushToTalkShortcut = shortcut
            persistActiveConfiguration(serverID: serverID)
            if !usesOverride(for: serverID) { encode(shortcut, key: "globalPushToTalkShortcut") }
            errorMessage = nil
        } catch {
            isPushToTalkEnabled = false
            defaults.set(false, forKey: "globalPushToTalkEnabled")
            errorMessage = error.localizedDescription
        }
    }

    func setPushToMuteEnabled(_ enabled: Bool) {
        configurePushToMute(enabled: enabled)
        guard errorMessage == nil else { return }
        isPushToMuteEnabled = enabled
        defaults.set(enabled, forKey: "pushToMuteEnabled")
    }

    func setPushToMuteShortcut(_ shortcut: GlobalHotKeyShortcut, serverID: UUID?) {
        do {
            if pushToMuteHotKey == nil {
                pushToMuteHotKey = try makeHotKey(shortcut: shortcut, identifier: 2) { [weak self] in
                    self?.handlers?.pushToMute($0)
                }
            } else {
                try pushToMuteHotKey?.setShortcut(shortcut)
            }
            pushToMuteShortcut = shortcut
            persistActiveConfiguration(serverID: serverID)
            if !usesOverride(for: serverID) { encode(shortcut, key: "pushToMuteShortcut") }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAudioShortcutsEnabled(_ enabled: Bool) {
        configureAudioShortcuts(enabled: enabled)
        guard errorMessage == nil else { return }
        areAudioShortcutsEnabled = enabled
        defaults.set(enabled, forKey: "globalAudioShortcutsEnabled")
    }

    func setAudioShortcut(_ shortcut: GlobalHotKeyShortcut, action: GlobalAudioShortcutAction, serverID: UUID?) {
        do {
            if let hotKey = audioHotKeys[action] {
                try hotKey.setShortcut(shortcut)
            } else {
                audioHotKeys[action] = try makeHotKey(shortcut: shortcut, identifier: action.hotKeyID) { [weak self] pressed in
                    if pressed { self?.handlers?.audioAction(action) }
                }
            }
            audioShortcuts[action] = shortcut
            persistActiveConfiguration(serverID: serverID)
            if !usesOverride(for: serverID) { encode(audioShortcuts, key: "globalAudioShortcuts") }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setIdleAction(_ action: IdleAudioAction) {
        idleAction = action
        didPerformIdleAction = false
        defaults.set(action.rawValue, forKey: "idleAudioAction")
    }

    func setIdleTimeoutMinutes(_ minutes: Int) {
        idleTimeoutMinutes = min(240, max(1, minutes))
        didPerformIdleAction = false
        defaults.set(idleTimeoutMinutes, forKey: "idleTimeoutMinutes")
    }

    func setVoiceTarget(_ target: ConfiguredVoiceTarget?) {
        voiceTarget = target
        if let target {
            encode(target, key: "configuredVoiceTarget")
        } else {
            defaults.removeObject(forKey: "configuredVoiceTarget")
        }
    }

    func setWhisperEnabled(_ enabled: Bool) {
        configureWhisper(enabled: enabled)
        guard errorMessage == nil else { return }
        isWhisperEnabled = enabled
        defaults.set(enabled, forKey: "whisperShortcutEnabled")
    }

    func setWhisperShortcut(_ shortcut: GlobalHotKeyShortcut, serverID: UUID?) {
        do {
            if whisperHotKey == nil {
                whisperHotKey = try makeHotKey(shortcut: shortcut, identifier: 20) { [weak self] in
                    self?.handlers?.whisper($0)
                }
            } else {
                try whisperHotKey?.setShortcut(shortcut)
            }
            whisperShortcut = shortcut
            persistActiveConfiguration(serverID: serverID)
            if !usesOverride(for: serverID) { encode(shortcut, key: "whisperShortcut") }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var currentConfiguration: ServerShortcutConfiguration {
        ServerShortcutConfiguration(
            pushToTalk: pushToTalkShortcut,
            pushToMute: pushToMuteShortcut,
            audio: audioShortcuts,
            whisper: whisperShortcut
        )
    }

    private func persistActiveConfiguration(serverID: UUID?) {
        let configuration = currentConfiguration
        if let key = serverID?.uuidString, serverOverrides[key] != nil {
            serverOverrides[key] = configuration
            persistOverrides()
        } else {
            globalConfiguration = configuration
        }
    }

    private func persistOverrides() {
        encode(serverOverrides, key: "serverShortcutOverrides")
    }

    private func configurePushToTalk(enabled: Bool) {
        do {
            if pushToTalkHotKey == nil {
                pushToTalkHotKey = try makeHotKey(shortcut: pushToTalkShortcut, identifier: 1) { [weak self] in
                    self?.handlers?.pushToTalk($0)
                }
            }
            try pushToTalkHotKey?.setEnabled(enabled)
            errorMessage = nil
        } catch {
            isPushToTalkEnabled = false
            defaults.set(false, forKey: "globalPushToTalkEnabled")
            errorMessage = error.localizedDescription
        }
    }

    private func configurePushToMute(enabled: Bool) {
        do {
            if pushToMuteHotKey == nil {
                pushToMuteHotKey = try makeHotKey(shortcut: pushToMuteShortcut, identifier: 2) { [weak self] in
                    self?.handlers?.pushToMute($0)
                }
            }
            try pushToMuteHotKey?.setEnabled(enabled)
            if !enabled { handlers?.pushToMute(false) }
            errorMessage = nil
        } catch {
            isPushToMuteEnabled = false
            defaults.set(false, forKey: "pushToMuteEnabled")
            errorMessage = error.localizedDescription
        }
    }

    private func configureAudioShortcuts(enabled: Bool) {
        do {
            for action in GlobalAudioShortcutAction.allCases {
                if audioHotKeys[action] == nil, let shortcut = audioShortcuts[action] {
                    audioHotKeys[action] = try makeHotKey(shortcut: shortcut, identifier: action.hotKeyID) { [weak self] pressed in
                        if pressed { self?.handlers?.audioAction(action) }
                    }
                }
                try audioHotKeys[action]?.setEnabled(enabled)
            }
            errorMessage = nil
        } catch {
            audioHotKeys.values.forEach { try? $0.setEnabled(false) }
            areAudioShortcutsEnabled = false
            defaults.set(false, forKey: "globalAudioShortcutsEnabled")
            errorMessage = error.localizedDescription
        }
    }

    private func configureWhisper(enabled: Bool) {
        do {
            if whisperHotKey == nil {
                whisperHotKey = try makeHotKey(shortcut: whisperShortcut, identifier: 20) { [weak self] in
                    self?.handlers?.whisper($0)
                }
            }
            try whisperHotKey?.setEnabled(enabled)
            if !enabled { handlers?.whisper(false) }
            errorMessage = nil
        } catch {
            isWhisperEnabled = false
            defaults.set(false, forKey: "whisperShortcutEnabled")
            errorMessage = error.localizedDescription
        }
    }

    private func makeHotKey(
        shortcut: GlobalHotKeyShortcut,
        identifier: UInt32,
        handler: @escaping @MainActor (Bool) -> Void
    ) throws -> GlobalPushToTalkHotKey {
        try GlobalPushToTalkHotKey(
            shortcut: shortcut,
            identifierID: identifier,
            onPressedChanged: handler
        )
    }

    private func startIdleMonitor() {
        idleMonitorTask?.cancel()
        idleMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, idleAction != .none else { continue }
                let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
                if seconds < Double(idleTimeoutMinutes * 60) {
                    didPerformIdleAction = false
                } else if !didPerformIdleAction {
                    didPerformIdleAction = true
                    handlers?.idleAction(idleAction)
                }
            }
        }
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
