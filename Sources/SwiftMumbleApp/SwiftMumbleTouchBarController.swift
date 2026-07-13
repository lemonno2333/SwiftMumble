import AppKit

@MainActor
final class SwiftMumbleTouchBarController: NSObject, NSTouchBarDelegate {
    weak var session: SessionStore?

    private var pushToTalkButton = NSButton()
    private let pushToTalkItem = NSPopoverTouchBarItem(identifier: .pushToTalk)
    private let muteButton = NSButton()
    private let deafenButton = NSButton()
    private let pushToTalkModeButton = NSButton()
    private let voiceActivityModeButton = NSButton()
    private let continuousModeButton = NSButton()
    private let transmissionModeHintLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let speakerLabel = NSTextField(labelWithString: "")
    private var refreshTimer: Timer?
    private lazy var touchBar: NSTouchBar = buildTouchBar()
    private lazy var transmissionModeTouchBar: NSTouchBar = buildTransmissionModeTouchBar()
    private var lastTransmitting: Bool?
    private var lastTransmissionMode: AudioTransmissionMode?

    init(session: SessionStore) {
        self.session = session
        super.init()
        configureViews()
        refresh(force: true)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func makeTouchBar() -> NSTouchBar { touchBar }

    private func buildTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.customizationIdentifier = .swiftMumble
        touchBar.defaultItemIdentifiers = [
            .pushToTalk,
            .fixedSpaceSmall,
            .mute,
            .deafen,
            .flexibleSpace,
            .speaker,
            .fixedSpaceSmall,
            .connection
        ]
        touchBar.customizationAllowedItemIdentifiers = [
            .pushToTalk, .mute, .deafen, .speaker, .connection
        ]
        return touchBar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .pushToTalk:
            pushToTalkItem.customizationLabel = L10n.text("touchBar.customize.talk")
            return pushToTalkItem
        case .mute:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = muteButton
            item.customizationLabel = L10n.text("touchBar.customize.mute")
            return item
        case .deafen:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = deafenButton
            item.customizationLabel = L10n.text("touchBar.customize.deafen")
            return item
        case .pushToTalkMode:
            let item = NSCustomTouchBarItem(identifier: identifier); item.view = pushToTalkModeButton; return item
        case .voiceActivityMode:
            let item = NSCustomTouchBarItem(identifier: identifier); item.view = voiceActivityModeButton; return item
        case .continuousMode:
            let item = NSCustomTouchBarItem(identifier: identifier); item.view = continuousModeButton; return item
        case .transmissionModeHint:
            let item = NSCustomTouchBarItem(identifier: identifier); item.view = transmissionModeHintLabel; return item
        case .speaker:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = speakerLabel
            item.customizationLabel = L10n.text("touchBar.customize.speaker")
            return item
        case .connection:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = statusLabel
            item.customizationLabel = L10n.text("touchBar.customize.connection")
            return item
        default: return nil
        }
    }

    private func configureViews() {
        muteButton.target = self
        muteButton.action = #selector(toggleMute)
        muteButton.imagePosition = .imageOnly

        deafenButton.target = self
        deafenButton.action = #selector(toggleDeafen)
        deafenButton.imagePosition = .imageOnly

        pushToTalkButton.target = self
        pushToTalkButton.action = #selector(togglePushToTalk)
        pushToTalkButton.imagePosition = .imageLeading
        pushToTalkButton.addGestureRecognizer(pushToTalkItem.makeStandardActivatePopoverGestureRecognizer())
        pushToTalkItem.collapsedRepresentation = pushToTalkButton

        configureModeButton(
            pushToTalkModeButton,
            title: L10n.text("audio.pushToTalk"),
            symbol: "mic.badge.plus",
            action: #selector(selectPushToTalkMode)
        )
        configureModeButton(
            voiceActivityModeButton,
            title: L10n.text("settings.voiceActivity"),
            symbol: "waveform.badge.mic",
            action: #selector(selectVoiceActivityMode)
        )
        configureModeButton(
            continuousModeButton,
            title: L10n.text("settings.continuous"),
            symbol: "dot.radiowaves.left.and.right",
            action: #selector(selectContinuousMode)
        )
        pushToTalkItem.popoverTouchBar = transmissionModeTouchBar
        pushToTalkItem.pressAndHoldTouchBar = transmissionModeTouchBar
        pushToTalkItem.showsCloseButton = true

        transmissionModeHintLabel.stringValue = L10n.text("touchBar.modeHint")
        transmissionModeHintLabel.alignment = .center
        transmissionModeHintLabel.font = .systemFont(ofSize: 11, weight: .medium)
        transmissionModeHintLabel.textColor = .secondaryLabelColor

        for label in [speakerLabel, statusLabel] {
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.font = .systemFont(ofSize: 12, weight: .medium)
        }
        speakerLabel.maximumNumberOfLines = 1
        speakerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
    }

    private func refresh(force: Bool = false) {
        guard let session else { return }
        let reconnecting = session.isReconnecting
        let connected: Bool
        if !reconnecting, case .connected = session.connectionState { connected = true } else { connected = false }

        if force || lastTransmitting != session.isTransmitting || lastTransmissionMode != session.transmissionMode {
            lastTransmitting = session.isTransmitting
            lastTransmissionMode = session.transmissionMode
            let title: String
            if session.transmissionMode == .voiceActivity {
                title = L10n.text(session.isTransmitting ? "touchBar.speakingNow" : "touchBar.notSpeaking")
            } else if session.transmissionMode == .continuous {
                title = L10n.text("touchBar.speakingNow")
            } else {
                title = L10n.text("audio.pushToTalk")
            }
            pushToTalkButton.title = title
            pushToTalkButton.image = NSImage(
                systemSymbolName: session.isTransmitting ? "waveform" : "mic.badge.plus",
                accessibilityDescription: title
            )
            let isPushToTalk = session.transmissionMode == .pushToTalk
            pushToTalkButton.bezelColor = session.isTransmitting
                ? .systemGreen
                : isPushToTalk ? .controlAccentColor : nil
            pushToTalkButton.contentTintColor = isPushToTalk ? nil : .disabledControlTextColor
            pushToTalkButton.state = session.isTransmitting ? .on : .off
        }
        pushToTalkButton.isEnabled = connected && !session.isMuted

        if force || lastTransmissionMode == session.transmissionMode {
            for (button, mode) in [
                (pushToTalkModeButton, AudioTransmissionMode.pushToTalk),
                (voiceActivityModeButton, AudioTransmissionMode.voiceActivity),
                (continuousModeButton, AudioTransmissionMode.continuous)
            ] {
                button.bezelColor = mode == session.transmissionMode ? .controlAccentColor : nil
                button.state = mode == session.transmissionMode ? .on : .off
            }
        }
        for button in [pushToTalkModeButton, voiceActivityModeButton, continuousModeButton] {
            button.isEnabled = connected && !session.isMuted
        }

        muteButton.image = NSImage(
            systemSymbolName: session.isMuted ? "mic.slash.fill" : "mic.fill",
            accessibilityDescription: session.isMuted ? L10n.text("audio.unmute") : L10n.text("audio.mute")
        )
        muteButton.bezelColor = session.isMuted ? .systemRed : nil
        muteButton.toolTip = session.isMuted ? L10n.text("audio.unmute") : L10n.text("audio.mute")

        deafenButton.image = NSImage(
            systemSymbolName: session.isDeafened ? "speaker.slash.fill" : "speaker.wave.2.fill",
            accessibilityDescription: session.isDeafened ? L10n.text("audio.undeafen") : L10n.text("audio.deafen")
        )
        deafenButton.bezelColor = session.isDeafened ? .systemRed : nil
        deafenButton.toolTip = session.isDeafened ? L10n.text("audio.undeafen") : L10n.text("audio.deafen")

        let speakers = session.talkingUserNames
        speakerLabel.stringValue = speakers.isEmpty
            ? L10n.text("touchBar.noSpeaker")
            : L10n.text("touchBar.speaking", speakers.joined(separator: ", "))
        speakerLabel.textColor = speakers.isEmpty ? .secondaryLabelColor : .systemGreen
        statusLabel.stringValue = session.transportLabel
        statusLabel.textColor = reconnecting ? .systemOrange : connected ? .labelColor : .secondaryLabelColor
        statusLabel.toolTip = reconnecting ? session.connectionLabel : nil
    }

    @objc private func toggleMute() { session?.toggleMute() }
    @objc private func toggleDeafen() { session?.toggleDeafen() }
    @objc private func togglePushToTalk() {
        guard session?.transmissionMode == .pushToTalk else { return }
        session?.toggleLatchedPushToTalk()
        refresh(force: true)
    }

    @objc private func selectPushToTalkMode() { selectTransmissionMode(.pushToTalk) }
    @objc private func selectVoiceActivityMode() { selectTransmissionMode(.voiceActivity) }
    @objc private func selectContinuousMode() { selectTransmissionMode(.continuous) }

    private func selectTransmissionMode(_ mode: AudioTransmissionMode) {
        session?.setTransmissionMode(mode)
        pushToTalkItem.dismissPopover(nil)
        refresh(force: true)
    }

    private func buildTransmissionModeTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            .pushToTalkMode,
            .fixedSpaceSmall,
            .voiceActivityMode,
            .fixedSpaceSmall,
            .continuousMode,
            .fixedSpaceSmall,
            .transmissionModeHint
        ]
        return touchBar
    }

    private func configureModeButton(
        _ button: NSButton,
        title: String,
        symbol: String,
        action: Selector
    ) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.target = self
        button.action = action
    }

}

private extension NSTouchBar.CustomizationIdentifier {
    static let swiftMumble = NSTouchBar.CustomizationIdentifier("com.leo.SwiftMumble.touchBar")
}

private extension NSTouchBarItem.Identifier {
    static let pushToTalk = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.pushToTalk")
    static let mute = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.mute")
    static let deafen = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.deafen")
    static let transmissionMode = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.transmissionMode")
    static let pushToTalkMode = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.mode.pushToTalk")
    static let voiceActivityMode = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.mode.voiceActivity")
    static let continuousMode = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.mode.continuous")
    static let transmissionModeHint = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.mode.hint")
    static let speaker = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.speaker")
    static let connection = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.connection")
}
