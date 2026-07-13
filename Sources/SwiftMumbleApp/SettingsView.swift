import AppKit
import MumbleAudio
import MumbleProtocol
import MumbleSystem
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var inputDevices: [AudioDeviceInfo] = []
    @State private var outputDevices: [AudioDeviceInfo] = []
    @State private var deviceError: String?
    @State private var isConfirmingIdentityRegeneration = false
    @State private var identityTransfer: IdentityTransfer?
    @State private var isChoosingIdentityFile = false
    @State private var exportDocument: PKCS12Document?
    @State private var isExportingIdentity = false
    @State private var identityTransferError: String?
    @State private var proxyPassword = ""
    @State private var selectedTab = SettingsTab.audio

    var body: some View {
        TabView(selection: $selectedTab) {
            Form {
                Picker(L10n.text("settings.transmission"), selection: transmissionModeSelection) {
                    Text(L10n.text("audio.pushToTalk")).tag(AudioTransmissionMode.pushToTalk)
                    Text(L10n.text("settings.voiceActivity")).tag(AudioTransmissionMode.voiceActivity)
                    Text(L10n.text("settings.continuous")).tag(AudioTransmissionMode.continuous)
                }
                if session.transmissionMode == .pushToTalk {
                    LabeledContent(L10n.text("settings.pushToTalkHold")) {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(session.pushToTalkHoldMilliseconds) },
                                    set: { session.setPushToTalkHoldMilliseconds(Int($0.rounded())) }
                                ),
                                in: 0 ... 1_000,
                                step: 50
                            )
                            Text(L10n.text("settings.milliseconds", session.pushToTalkHoldMilliseconds))
                                .font(.caption.monospacedDigit())
                                .frame(width: 72, alignment: .trailing)
                        }
                    }
                }
                Toggle(
                    L10n.text("settings.pttDoubleClickContinuous"),
                    isOn: Binding(
                        get: { session.doubleClickPTTTogglesContinuous },
                        set: { session.setDoubleClickPTTTogglesContinuous($0) }
                    )
                )
                Picker(L10n.text("settings.inputDevice"), selection: inputSelection) {
                    Text(L10n.text("settings.systemDefault")).tag(UInt32?.none)
                    ForEach(inputDevices) { device in
                        Text(device.isDefault ? L10n.text("settings.deviceDefault", device.name) : device.name)
                            .tag(Optional(device.id))
                    }
                }
                Picker(L10n.text("settings.outputDevice"), selection: outputSelection) {
                    Text(L10n.text("settings.systemDefault")).tag(UInt32?.none)
                    ForEach(outputDevices) { device in
                        Text(device.isDefault ? L10n.text("settings.deviceDefault", device.name) : device.name)
                            .tag(Optional(device.id))
                    }
                }
                LabeledContent(L10n.text("settings.jitterBuffer")) {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(session.jitterBufferDelayFrames) },
                                set: { session.setJitterBufferDelayFrames(Int($0.rounded())) }
                            ),
                            in: 1 ... 10,
                            step: 1
                        )
                        Text(L10n.text("settings.milliseconds", session.jitterBufferDelayFrames * 10))
                            .font(.caption.monospacedDigit())
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                LabeledContent(L10n.text("settings.masterOutputVolume")) {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { session.masterOutputVolume },
                                set: { session.setMasterOutputVolume($0) }
                            ),
                            in: 0 ... 2,
                            step: 0.05
                        )
                        Text(L10n.text("user.volume.percent", Int((session.masterOutputVolume * 100).rounded())))
                            .font(.caption.monospacedDigit())
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Toggle(
                    L10n.text("settings.ducking"),
                    isOn: Binding(
                        get: { session.duckingEnabled },
                        set: { session.setDuckingEnabled($0) }
                    )
                )
                if session.duckingEnabled {
                    LabeledContent(L10n.text("settings.duckingVolume")) {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { session.duckingVolume },
                                    set: { session.setDuckingVolume($0) }
                                ),
                                in: 0 ... 1,
                                step: 0.05
                            )
                            Text(L10n.text("user.volume.percent", Int((session.duckingVolume * 100).rounded())))
                                .font(.caption.monospacedDigit())
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
                if session.transmissionMode == .voiceActivity {
                    VoiceActivitySettingsView()
                        .environment(session)
                }
                Toggle(
                    L10n.text("settings.noiseSuppression"),
                    isOn: Binding(
                        get: { session.noiseSuppressionEnabled },
                        set: { session.setNoiseSuppressionEnabled($0) }
                    )
                )
                Toggle(
                    L10n.text("settings.automaticGainControl"),
                    isOn: Binding(
                        get: { session.automaticGainControlEnabled },
                        set: { session.setAutomaticGainControlEnabled($0) }
                    )
                )
                Toggle(
                    L10n.text("settings.echoCancellation"),
                    isOn: Binding(get: { session.echoCancellationEnabled }, set: { session.setEchoCancellationEnabled($0) })
                )
                Text(L10n.text("settings.noiseSuppression.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup(L10n.text("settings.opus.title")) {
                    LabeledContent(L10n.text("settings.opus.bitrate")) {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(session.opusBitrateKbps) },
                                    set: { session.setOpusBitrateKbps(Int($0.rounded())) }
                                ),
                                in: 12 ... 128,
                                step: 4
                            )
                            Text(L10n.text("settings.opus.kbps", session.opusBitrateKbps))
                                .font(.caption.monospacedDigit())
                                .frame(width: 82, alignment: .trailing)
                        }
                    }
                    LabeledContent(L10n.text("settings.opus.complexity")) {
                        Stepper(
                            "\(session.opusComplexity)",
                            value: Binding(
                                get: { session.opusComplexity },
                                set: { session.setOpusComplexity($0) }
                            ),
                            in: 0 ... 10
                        )
                    }
                    LabeledContent(L10n.text("settings.opus.packetLoss")) {
                        Stepper(
                            L10n.text("user.volume.percent", session.opusExpectedPacketLossPercent),
                            value: Binding(
                                get: { session.opusExpectedPacketLossPercent },
                                set: { session.setOpusExpectedPacketLossPercent($0) }
                            ),
                            in: 0 ... 30,
                            step: 5
                        )
                    }
                    Toggle(
                        L10n.text("settings.opus.fec"),
                        isOn: Binding(
                            get: { session.opusInbandFECEnabled },
                            set: { session.setOpusInbandFECEnabled($0) }
                        )
                    )
                    Toggle(
                        L10n.text("settings.opus.lowLatency"),
                        isOn: Binding(
                            get: { session.opusLowLatencyEnabled },
                            set: { session.setOpusLowLatencyEnabled($0) }
                        )
                    )
                    Picker(L10n.text("settings.opus.packetDuration"), selection: Binding(
                        get: { session.opusFramesPerPacket }, set: { session.setOpusFramesPerPacket($0) }
                    )) {
                        Text("10 ms").tag(1)
                        Text("20 ms").tag(2)
                        Text("40 ms").tag(4)
                        Text("60 ms").tag(6)
                    }
                    Text(L10n.text("settings.opus.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(
                    L10n.text("settings.audioCues"),
                    isOn: Binding(
                        get: { session.audioCuesEnabled },
                        set: { session.setAudioCuesEnabled($0) }
                    )
                )
                Text(L10n.text("settings.audioCues.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(
                        session.audioLoopbackTestPhase == .idle
                            ? L10n.text("settings.audioTest.start")
                            : L10n.text("settings.audioTest.cancel"),
                        systemImage: session.audioLoopbackTestPhase == .playing
                            ? "speaker.wave.2.fill"
                            : "waveform.and.mic"
                    ) {
                        if session.audioLoopbackTestPhase == .idle {
                            session.startAudioLoopbackTest()
                        } else {
                            session.cancelAudioLoopbackTest()
                        }
                    }
                    if session.audioLoopbackTestPhase != .idle {
                        ProgressView()
                            .controlSize(.small)
                        Text(
                            session.audioLoopbackTestPhase == .recording
                                ? L10n.text("settings.audioTest.recording")
                                : L10n.text("settings.audioTest.playing")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Text(L10n.text("settings.audioTest.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n.text("audioWizard.open"), systemImage: "wand.and.stars") {
                    session.isShowingAudioWizard = true
                }
                DisclosureGroup(L10n.text("audioStats.title")) {
                    LabeledContent(L10n.text("audioStats.inputLevel"), value: String(format: "%.1f dB", session.microphoneLevelDB))
                    LabeledContent(L10n.text("audioStats.sent"), value: "\(session.audioPacketsSent)")
                    LabeledContent(L10n.text("audioStats.received"), value: "\(session.audioPacketsReceived)")
                    LabeledContent(L10n.text("audioStats.speakers"), value: "\(session.activeReceivePipelineCount)")
                    LabeledContent(L10n.text("audioStats.jitter"), value: String(format: "%.1f ms", session.averageReceiveJitterMilliseconds))
                    LabeledContent(L10n.text("audioStats.buffer"), value: "\(session.averageReceiveBufferMilliseconds) ms")
                }
                Toggle(
                    L10n.text("settings.muteMicrophone"),
                    isOn: Binding(get: { session.isMuted }, set: { session.setMuted($0) })
                )
                Toggle(
                    L10n.text("settings.unmuteOnUndeafen"),
                    isOn: Binding(
                        get: { session.unmuteOnUndeafen },
                        set: { session.setUnmuteOnUndeafen($0) }
                    )
                )
                if let deviceError {
                    Text(deviceError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label(L10n.text("settings.audio"), systemImage: "waveform") }
            .tag(SettingsTab.audio)

            connectionSettings
                .tabItem { Label(L10n.text("settings.connection"), systemImage: "network") }
                .tag(SettingsTab.connection)

            interfaceSettings
                .tabItem { Label(L10n.text("settings.interface"), systemImage: "paintbrush") }
                .tag(SettingsTab.interface)

            shortcutSettings
                .tabItem { Label(L10n.text("settings.shortcuts"), systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            identityView
                .tabItem { Label(L10n.text("settings.identity"), systemImage: "person.badge.key") }
                .tag(SettingsTab.identity)
        }
        .frame(width: 580, height: 420)
        .padding()
        .task { loadDevices() }
        .onAppear { session.setAudioSettingsVisible(selectedTab == .audio) }
        .onChange(of: selectedTab) { _, tab in
            session.setAudioSettingsVisible(tab == .audio)
        }
        .onDisappear { session.setAudioSettingsVisible(false) }
        .sheet(isPresented: Binding(
            get: { session.isShowingAudioWizard },
            set: { session.isShowingAudioWizard = $0 }
        )) {
            AudioSetupAssistantView().environment(session)
        }
        .confirmationDialog(
            L10n.text("identity.regenerate.title"),
            isPresented: $isConfirmingIdentityRegeneration,
            titleVisibility: .visible
        ) {
            Button(L10n.text("identity.regenerate.action"), role: .destructive) {
                session.regenerateClientIdentity()
            }
        } message: {
            Text(L10n.text("identity.regenerate.message"))
        }
        .fileImporter(
            isPresented: $isChoosingIdentityFile,
            allowedContentTypes: [.pkcs12],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                identityTransfer = .importIdentity(try Data(contentsOf: url))
            } catch {
                identityTransferError = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isExportingIdentity,
            document: exportDocument,
            contentType: .pkcs12,
            defaultFilename: "SwiftMumble-Identity"
        ) { result in
            if case .failure(let error) = result {
                identityTransferError = error.localizedDescription
            }
            exportDocument = nil
        }
        .sheet(item: $identityTransfer) { transfer in
            IdentityPasswordView(transfer: transfer) { password in
                do {
                    switch transfer {
                    case .exportIdentity:
                        exportDocument = PKCS12Document(
                            data: try session.exportClientIdentity(passphrase: password)
                        )
                        identityTransfer = nil
                        isExportingIdentity = true
                    case .importIdentity(let data):
                        try session.importClientIdentity(data, passphrase: password)
                        identityTransfer = nil
                    }
                } catch {
                    identityTransferError = error.localizedDescription
                }
            }
        }
        .alert(
            L10n.text("identity.transfer.errorTitle"),
            isPresented: Binding(
                get: { identityTransferError != nil },
                set: { if !$0 { identityTransferError = nil } }
            )
        ) {
            Button(L10n.text("common.ok")) { identityTransferError = nil }
        } message: {
            Text(identityTransferError ?? L10n.text("error.unknown"))
        }
    }

    private var connectionSettings: some View {
        Form {
            Toggle(
                L10n.text("settings.autoReconnect"),
                isOn: Binding(
                    get: { session.autoReconnectEnabled },
                    set: { session.setAutoReconnectEnabled($0) }
                )
            )
            Toggle(
                L10n.text("settings.publicServers"),
                isOn: Binding(
                    get: { session.publicServerDirectoryEnabled },
                    set: { session.setPublicServerDirectoryEnabled($0) }
                )
            )
            Text(L10n.text("settings.publicServers.privacy"))
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent(L10n.text("settings.connectionTimeout")) {
                Stepper(
                    L10n.text("settings.seconds", session.connectionTimeoutSeconds),
                    value: Binding(
                        get: { session.connectionTimeoutSeconds },
                        set: { session.setConnectionTimeoutSeconds($0) }
                    ),
                    in: 5 ... 120,
                    step: 5
                )
            }
            LabeledContent(L10n.text("settings.pingInterval")) {
                Stepper(
                    L10n.text("settings.seconds", session.controlPingIntervalSeconds),
                    value: Binding(
                        get: { session.controlPingIntervalSeconds },
                        set: { session.setControlPingIntervalSeconds($0) }
                    ),
                    in: 5 ... 60,
                    step: 5
                )
            }
            DisclosureGroup(L10n.text("settings.proxy")) {
                Picker(L10n.text("settings.proxy.type"), selection: Binding(
                    get: { session.proxyType }, set: { session.proxyType = $0 }
                )) {
                    Text(L10n.text("settings.proxy.none")).tag(MumbleProxyType.none)
                    Text("SOCKS5").tag(MumbleProxyType.socks5)
                    Text("HTTP CONNECT").tag(MumbleProxyType.httpConnect)
                }
                if session.proxyType != .none {
                    TextField(
                        L10n.text("settings.proxy.host"),
                        text: Binding(get: { session.proxyHost }, set: { session.proxyHost = $0 })
                    )
                    TextField(
                        L10n.text("settings.proxy.port"),
                        value: Binding(
                            get: { Int(session.proxyPort) },
                            set: { session.proxyPort = UInt16(clamping: $0) }
                        ),
                        format: .number
                    )
                    TextField(
                        L10n.text("settings.proxy.username"),
                        text: Binding(get: { session.proxyUsername }, set: { session.proxyUsername = $0 })
                    )
                    SecureField(L10n.text("settings.proxy.password"), text: $proxyPassword)
                }
                Button(L10n.text("settings.proxy.save")) {
                    session.saveProxy(
                        type: session.proxyType,
                        host: session.proxyHost,
                        port: session.proxyPort,
                        username: session.proxyUsername,
                        password: proxyPassword
                    )
                    proxyPassword = ""
                }
                Text(L10n.text("settings.proxy.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if session.serverSuggestedPushToTalk != nil
                || session.serverSuggestedPositionalAudio != nil
                || session.serverSuggestedVersion != nil {
                DisclosureGroup(L10n.text("settings.serverSuggestions")) {
                    if let ptt = session.serverSuggestedPushToTalk {
                        LabeledContent(
                            L10n.text("settings.serverSuggestions.ptt"),
                            value: ptt ? L10n.text("common.yes") : L10n.text("common.no")
                        )
                    }
                    if let positional = session.serverSuggestedPositionalAudio {
                        LabeledContent(
                            L10n.text("settings.serverSuggestions.positional"),
                            value: positional ? L10n.text("common.yes") : L10n.text("common.no")
                        )
                    }
                    if let version = session.serverSuggestedVersion {
                        LabeledContent(L10n.text("settings.serverSuggestions.version"), value: "\(version)")
                    }
                    Text(L10n.text("settings.serverSuggestions.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var interfaceSettings: some View {
        Form {
            Section(L10n.text("settings.touchBar")) {
                Toggle(
                    L10n.text("settings.touchBar.controlStrip"),
                    isOn: Binding(
                        get: { session.touchBarControlStripEnabled },
                        set: { session.setTouchBarControlStripEnabled($0) }
                    )
                )
                Text(L10n.text("settings.touchBar.controlStrip.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n.text("settings.touchBar.customize")) {
                    NSApplication.shared.toggleTouchBarCustomizationPalette(nil)
                }
            }
            Toggle(
                L10n.text("settings.notifications"),
                isOn: Binding(
                    get: { session.notificationsEnabled },
                    set: { session.setNotificationsEnabled($0) }
                )
            )
            Text(L10n.text("settings.notifications.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(
                L10n.text("settings.textToSpeech"),
                isOn: Binding(
                    get: { session.textToSpeechEnabled },
                    set: { session.setTextToSpeechEnabled($0) }
                )
            )
            Text(L10n.text("settings.textToSpeech.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent(L10n.text("settings.chatLogLimit")) {
                Stepper(
                    "\(session.chatLogLimit)",
                    value: Binding(
                        get: { session.chatLogLimit },
                        set: { session.setChatLogLimit($0) }
                    ),
                    in: 50 ... 5_000,
                    step: 50
                )
            }
            Toggle(
                L10n.text("settings.chat24Hour"),
                isOn: Binding(
                    get: { session.chatUses24HourTime },
                    set: { session.setChatUses24HourTime($0) }
                )
            )
            Picker(L10n.text("settings.channelExpansion"), selection: Binding(
                get: { session.channelExpansionPolicy },
                set: { session.setChannelExpansionPolicy($0) }
            )) {
                Text(L10n.text("settings.channelExpansion.current")).tag(ChannelExpansionPolicy.currentPath)
                Text(L10n.text("settings.channelExpansion.all")).tag(ChannelExpansionPolicy.all)
                Text(L10n.text("settings.channelExpansion.collapsed")).tag(ChannelExpansionPolicy.collapsed)
            }
            Toggle(
                L10n.text("settings.showReturnPreviousChannel"),
                isOn: Binding(
                    get: { session.showsReturnToPreviousChannelControl },
                    set: { session.setShowsReturnToPreviousChannelControl($0) }
                )
            )
            Toggle(
                L10n.text("settings.showHideEmptyChannels"),
                isOn: Binding(
                    get: { session.showsHideEmptyChannelsControl },
                    set: { session.setShowsHideEmptyChannelsControl($0) }
                )
            )
        }
        .formStyle(.grouped)
    }

    private var shortcutSettings: some View {
        Form {
            Toggle(
                L10n.text("settings.serverShortcuts"),
                isOn: Binding(
                    get: { session.selectedServerUsesShortcutOverride },
                    set: { session.setSelectedServerShortcutOverrideEnabled($0) }
                )
            )
            .disabled(session.selectedServer == nil)
            Text(L10n.text("settings.serverShortcuts.help", session.selectedServer?.name ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(
                L10n.text("settings.globalPushToTalk"),
                isOn: Binding(
                    get: { session.isGlobalPushToTalkEnabled },
                    set: { session.setGlobalPushToTalkEnabled($0) }
                )
            )
            .disabled(session.transmissionMode != .pushToTalk)
            LabeledContent(L10n.text("settings.globalShortcut")) {
                ShortcutRecorderView(
                    shortcut: session.globalPushToTalkShortcut,
                    onRecordingChanged: session.setRecordingGlobalShortcut,
                    onChange: session.setGlobalPushToTalkShortcut
                )
            }
            .disabled(session.transmissionMode != .pushToTalk)
            Text(L10n.text(
                "settings.globalPushToTalk.help",
                session.globalPushToTalkShortcut.displayName
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let shortcutError = session.globalPushToTalkError {
                Text(shortcutError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle(
                L10n.text("settings.pushToMute"),
                isOn: Binding(
                    get: { session.isPushToMuteEnabled },
                    set: { session.setPushToMuteEnabled($0) }
                )
            )
            LabeledContent(L10n.text("settings.pushToMuteShortcut")) {
                ShortcutRecorderView(
                    shortcut: session.pushToMuteShortcut,
                    onRecordingChanged: session.setRecordingPushToMuteShortcut,
                    onChange: session.setPushToMuteShortcut
                )
            }
            .disabled(!session.isPushToMuteEnabled)
            Toggle(
                L10n.text("settings.globalAudioShortcuts"),
                isOn: Binding(
                    get: { session.areGlobalAudioShortcutsEnabled },
                    set: { session.setGlobalAudioShortcutsEnabled($0) }
                )
            )
            ForEach(GlobalAudioShortcutAction.allCases) { action in
                LabeledContent(L10n.text("settings.shortcut.\(action.rawValue)")) {
                    ShortcutRecorderView(
                        shortcut: session.globalAudioShortcuts[action] ?? .default,
                        onRecordingChanged: session.setRecordingGlobalAudioShortcut,
                        onChange: { session.setGlobalAudioShortcut($0, for: action) }
                    )
                }
                .disabled(!session.areGlobalAudioShortcutsEnabled)
            }
            Toggle(
                L10n.text("settings.whisperShortcut"),
                isOn: Binding(
                    get: { session.isWhisperShortcutEnabled },
                    set: { session.setWhisperShortcutEnabled($0) }
                )
            )
            LabeledContent(L10n.text("settings.whisperKey")) {
                ShortcutRecorderView(
                    shortcut: session.whisperShortcut,
                    onRecordingChanged: session.setRecordingWhisperShortcut,
                    onChange: session.setWhisperShortcut
                )
            }
            .disabled(!session.isWhisperShortcutEnabled)
            if let target = session.configuredVoiceTarget {
                LabeledContent(L10n.text("settings.whisperTarget"), value: voiceTargetName(target))
                Button(L10n.text("settings.whisperClear"), role: .destructive) {
                    session.clearWhisperTarget()
                }
            } else {
                Text(L10n.text("settings.whisperTarget.none"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker(L10n.text("settings.idleAction"), selection: Binding(
                get: { session.idleAudioAction },
                set: { session.setIdleAudioAction($0) }
            )) {
                Text(L10n.text("settings.idle.none")).tag(IdleAudioAction.none)
                Text(L10n.text("settings.idle.mute")).tag(IdleAudioAction.mute)
                Text(L10n.text("settings.idle.deafen")).tag(IdleAudioAction.deafen)
            }
            if session.idleAudioAction != .none {
                LabeledContent(L10n.text("settings.idleTimeout")) {
                    Stepper(
                        L10n.text("settings.minutes", session.idleTimeoutMinutes),
                        value: Binding(
                            get: { session.idleTimeoutMinutes },
                            set: { session.setIdleTimeoutMinutes($0) }
                        ),
                        in: 1 ... 240
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    private var inputSelection: Binding<UInt32?> {
        Binding(
            get: { session.selectedInputDeviceID },
            set: { session.selectInputDevice($0) }
        )
    }

    private var transmissionModeSelection: Binding<AudioTransmissionMode> {
        Binding(
            get: { session.transmissionMode },
            set: { session.setTransmissionMode($0) }
        )
    }

    private func voiceTargetName(_ target: ConfiguredVoiceTarget) -> String {
        switch target {
        case .user(_, let name): return L10n.text("voice.target.user", name)
        case .channel(_, let name, _, let children):
            return L10n.text(children ? "voice.target.channelChildren" : "voice.target.channel", name)
        }
    }

    private var outputSelection: Binding<UInt32?> {
        Binding(
            get: { session.selectedOutputDeviceID },
            set: { session.selectOutputDevice($0) }
        )
    }

    @ViewBuilder
    private var identityView: some View {
        if let identity = session.clientIdentityInfo {
            Form {
                LabeledContent(L10n.text("identity.subject"), value: identity.subject)
                LabeledContent(L10n.text("identity.fingerprint")) {
                    Text(identity.fingerprintSHA256)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                if let notAfter = identity.notAfter {
                    LabeledContent(
                        L10n.text("identity.validUntil"),
                        value: notAfter.formatted(date: .long, time: .omitted)
                    )
                }
                if let serverHash = session.serverRecognizedIdentityHash {
                    LabeledContent(L10n.text("identity.serverHash")) {
                        VStack(alignment: .trailing, spacing: 3) {
                            Label(L10n.text("identity.serverRecognized"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(serverHash)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                Text(L10n.text("identity.keychain.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L10n.text("identity.import"), systemImage: "square.and.arrow.down") {
                        isChoosingIdentityFile = true
                    }
                    Button(L10n.text("identity.export"), systemImage: "square.and.arrow.up") {
                        identityTransfer = .exportIdentity
                    }
                    Spacer()
                    Button(L10n.text("identity.regenerate.action"), role: .destructive) {
                        isConfirmingIdentityRegeneration = true
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            VStack(spacing: 14) {
                ContentUnavailableView(
                    L10n.text("identity.empty"),
                    systemImage: "person.badge.key",
                    description: Text(session.clientIdentityError ?? L10n.text("identity.empty.help"))
                )
                Button(L10n.text("identity.retry")) {
                    session.retryClientIdentity()
                }
            }
        }
    }

    private func loadDevices() {
        do {
            inputDevices = try AudioDeviceManager.inputDevices()
            outputDevices = try AudioDeviceManager.outputDevices()
        } catch {
            deviceError = error.localizedDescription
        }
    }
}

private enum SettingsTab: Hashable {
    case audio
    case connection
    case interface
    case shortcuts
    case identity
}

private enum IdentityTransfer: Identifiable {
    case exportIdentity
    case importIdentity(Data)

    var id: String {
        switch self {
        case .exportIdentity: "export"
        case .importIdentity: "import"
        }
    }
}

private struct IdentityPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    let transfer: IdentityTransfer
    let confirm: (String) -> Void
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)

            Text(message)
                .foregroundStyle(.secondary)

            Form {
                SecureField(L10n.text("identity.transfer.password"), text: $password)
                if isExport {
                    SecureField(L10n.text("identity.transfer.confirmPassword"), text: $confirmation)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(L10n.text("common.cancel"), role: .cancel) { dismiss() }
                Button(actionTitle, role: isExport ? nil : .destructive) {
                    confirm(password)
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || (isExport && password != confirmation))
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var isExport: Bool {
        if case .exportIdentity = transfer { return true }
        return false
    }

    private var title: String {
        isExport ? L10n.text("identity.export.title") : L10n.text("identity.import.title")
    }

    private var message: String {
        isExport ? L10n.text("identity.export.message") : L10n.text("identity.import.message")
    }

    private var actionTitle: String {
        isExport ? L10n.text("identity.export.action") : L10n.text("identity.import.action")
    }

    private var symbol: String {
        isExport ? "lock.doc" : "person.badge.key"
    }
}
