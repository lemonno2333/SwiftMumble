import AppKit

@MainActor
final class SwiftMumbleTouchBarController: NSObject, NSTouchBarDelegate {
    weak var session: SessionStore?

    private var pushToTalkButton = NSButton()
    private let pushToTalkItem = NSCustomTouchBarItem(identifier: .pushToTalk)
    private let muteButton = NSButton()
    private let deafenButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let speakerLabel = NSTextField(labelWithString: "")
    private var refreshTimer: Timer?
    private lazy var touchBar: NSTouchBar = buildTouchBar()
    private var lastTransmitting: Bool?

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
        touchBar.customizationAllowedItemIdentifiers = [.pushToTalk, .mute, .deafen, .speaker, .connection]
        return touchBar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .pushToTalk: return pushToTalkItem
        case .mute:
            let item = NSCustomTouchBarItem(identifier: identifier); item.view = muteButton; return item
        case .deafen:
            let item = NSCustomTouchBarItem(identifier: identifier); item.view = deafenButton; return item
        case .speaker:
            let item = NSCustomTouchBarItem(identifier: identifier); item.view = speakerLabel; return item
        case .connection:
            let item = NSCustomTouchBarItem(identifier: identifier); item.view = statusLabel; return item
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
        let connected: Bool
        if case .connected = session.connectionState { connected = true } else { connected = false }

        if force || lastTransmitting != session.isTransmitting {
            lastTransmitting = session.isTransmitting
            let button = NSButton(title: L10n.text("audio.pushToTalk"), target: self, action: #selector(togglePushToTalk))
            button.image = NSImage(
                systemSymbolName: session.isTransmitting ? "waveform" : "mic.badge.plus",
                accessibilityDescription: L10n.text("audio.pushToTalk")
            )
            button.imagePosition = .imageLeading
            button.bezelColor = session.isTransmitting ? .systemGreen : .controlAccentColor
            button.state = session.isTransmitting ? .on : .off
            pushToTalkButton = button
            pushToTalkItem.view = button
        }
        pushToTalkButton.isEnabled = connected && !session.isMuted && session.transmissionMode == .pushToTalk

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
        statusLabel.textColor = connected ? .labelColor : .secondaryLabelColor
    }

    @objc private func toggleMute() { session?.toggleMute() }
    @objc private func toggleDeafen() { session?.toggleDeafen() }
    @objc private func togglePushToTalk() {
        session?.toggleLatchedPushToTalk()
        refresh(force: true)
    }
}

private extension NSTouchBar.CustomizationIdentifier {
    static let swiftMumble = NSTouchBar.CustomizationIdentifier("com.leo.SwiftMumble.touchBar")
}

private extension NSTouchBarItem.Identifier {
    static let pushToTalk = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.pushToTalk")
    static let mute = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.mute")
    static let deafen = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.deafen")
    static let speaker = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.speaker")
    static let connection = NSTouchBarItem.Identifier("com.leo.SwiftMumble.touchBar.connection")
}
