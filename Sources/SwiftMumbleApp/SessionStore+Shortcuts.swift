import Foundation
import MumbleProtocol
import MumbleSystem

extension SessionStore {
    func setSelectedServerShortcutOverrideEnabled(_ enabled: Bool) {
        shortcuts.setOverrideEnabled(enabled, for: selectedServerID)
    }

    func applyShortcutConfigurationForSelectedServer(rebind: Bool = true) {
        shortcuts.applyConfiguration(for: selectedServerID, rebind: rebind)
    }

    func setGlobalPushToTalkEnabled(_ enabled: Bool) {
        shortcuts.setPushToTalkEnabled(enabled)
    }

    func setGlobalPushToTalkShortcut(_ shortcut: GlobalHotKeyShortcut) {
        shortcuts.setPushToTalkShortcut(shortcut, serverID: selectedServerID)
    }

    func setPushToMuteEnabled(_ enabled: Bool) {
        shortcuts.setPushToMuteEnabled(enabled)
    }

    func setPushToMuteShortcut(_ shortcut: GlobalHotKeyShortcut) {
        shortcuts.setPushToMuteShortcut(shortcut, serverID: selectedServerID)
    }

    func setGlobalAudioShortcutsEnabled(_ enabled: Bool) {
        shortcuts.setAudioShortcutsEnabled(enabled)
    }

    func setGlobalAudioShortcut(
        _ shortcut: GlobalHotKeyShortcut,
        for action: GlobalAudioShortcutAction
    ) {
        shortcuts.setAudioShortcut(shortcut, action: action, serverID: selectedServerID)
    }

    func setIdleAudioAction(_ action: IdleAudioAction) {
        shortcuts.setIdleAction(action)
    }

    func setIdleTimeoutMinutes(_ minutes: Int) {
        shortcuts.setIdleTimeoutMinutes(minutes)
    }

    func setWhisperTarget(user: MumbleUser) {
        shortcuts.setVoiceTarget(.user(session: user.id, name: user.name))
    }

    func setWhisperTarget(channel: MumbleChannel, links: Bool, children: Bool) {
        shortcuts.setVoiceTarget(
            .channel(id: channel.id, name: channel.name, links: links, children: children)
        )
    }

    func clearWhisperTarget() {
        shortcuts.setVoiceTarget(nil)
    }

    func setWhisperShortcutEnabled(_ enabled: Bool) {
        shortcuts.setWhisperEnabled(enabled)
    }

    func setWhisperShortcut(_ shortcut: GlobalHotKeyShortcut) {
        shortcuts.setWhisperShortcut(shortcut, serverID: selectedServerID)
    }

    func bindShortcutHandlers() {
        shortcuts.bind(
            ShortcutController.Handlers(
                pushToTalk: { [weak self] pressed in
                    if pressed { self?.beginTransmission() }
                    else { self?.releasePushToTalk() }
                },
                pushToMute: { [weak self] pressed in
                    self?.handlePushToMute(pressed: pressed)
                },
                audioAction: { [weak self] action in
                    self?.performGlobalAudioShortcut(action)
                },
                whisper: { [weak self] pressed in
                    self?.handleWhisperShortcut(pressed: pressed)
                },
                idleAction: { [weak self] action in
                    switch action {
                    case .none: break
                    case .mute: self?.setMuted(true)
                    case .deafen: self?.setDeafened(true)
                    }
                }
            )
        )
    }

    func handlePushToMute(pressed: Bool) {
        if pressed {
            muteStateBeforePushToMute = isMuted
            endTransmission()
            setMuted(true)
        } else if isMuted != muteStateBeforePushToMute {
            setMuted(muteStateBeforePushToMute)
        }
    }

    func performGlobalAudioShortcut(_ action: GlobalAudioShortcutAction) {
        switch action {
        case .toggleMute: toggleMute()
        case .toggleDeafen: toggleDeafen()
        case .volumeDown: setMasterOutputVolume(masterOutputVolume - 0.05)
        case .volumeUp: setMasterOutputVolume(masterOutputVolume + 0.05)
        case .cycleTransmissionMode: cycleTransmissionMode()
        }
    }

    func handleWhisperShortcut(pressed: Bool) {
        isWhisperPressed = pressed
        if pressed {
            beginWhisperTransmission()
        } else if activeVoiceTargetID == 1 {
            if isTransmitting { endTransmission() }
            else { activeVoiceTargetID = 0 }
        }
    }

    func beginWhisperTransmission() {
        guard let configuredVoiceTarget = shortcuts.voiceTarget,
              !isMuted,
              case .connected = connectionState,
              transmissionMode == .pushToTalk,
              !isTransmitting else {
            return
        }
        let frame: MumbleFrame?
        switch configuredVoiceTarget {
        case .user(let session, _):
            frame = try? MumbleCommands.setVoiceTarget(id: 1, sessions: [session])
        case .channel(let id, _, let links, let children):
            frame = try? MumbleCommands.setVoiceTarget(
                id: 1,
                channelID: id,
                includeLinks: links,
                includeChildren: children
            )
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
}
