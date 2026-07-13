import MumbleProtocol
import SwiftUI

struct ChannelBrowser: View {
    @Environment(SessionStore.self) private var session
    @State private var highlightedChannelID: MumbleChannel.ID?
    @State private var highlightedUserID: UInt32?

    var body: some View {
        @Bindable var session = session

        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(session.visibleChannels) { channel in
                        ChannelNode(
                            channel: channel,
                            highlightedChannelID: $highlightedChannelID,
                            highlightedUserID: $highlightedUserID
                        )
                    }
                    Spacer(minLength: 40)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            highlightedChannelID = nil
                            highlightedUserID = nil
                        }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
        .toolbar {
            if session.showsHideEmptyChannelsControl {
                ToolbarItem(placement: .secondaryAction) {
                    Toggle(isOn: Binding(
                        get: { session.hideEmptyChannels },
                        set: { session.setHideEmptyChannels($0) }
                    )) {
                        Label(L10n.text("channel.hideEmpty"), systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .navigationTitle(session.selectedServer?.name ?? L10n.text("channels.title"))
        .navigationSubtitle(session.selectedServer.map { "\($0.host):\($0.port)" } ?? L10n.text("server.noneSelected"))
        .overlay {
            if session.channels.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySymbol,
                    description: Text(session.connectionDetail)
                )
            }
        }
        .sheet(item: $session.privateMessageTarget) { user in
            PrivateMessageComposer(user: user)
                .environment(session)
        }
        .popover(item: $session.userInformationTarget) { user in
            UserInformationView(user: user)
                .environment(session)
        }
        .sheet(item: $session.channelEditorRequest) { request in
            ChannelEditorView(request: request)
                .environment(session)
        }
        .sheet(item: $session.profileEditorTarget) { user in
            UserProfileEditorView(
                user: user,
                nickname: user.certificateHash.flatMap { session.localUserNicknames[$0] } ?? ""
            )
            .environment(session)
        }
        .sheet(item: $session.moderationRequest) { request in
            UserModerationView(request: request).environment(session)
        }
        .sheet(item: $session.aclEditorChannel) { channel in
            ACLManagementView(channel: channel).environment(session)
        }
        .confirmationDialog(
            L10n.text("channel.delete.title"),
            isPresented: Binding(
                get: { session.pendingChannelDeletion != nil },
                set: { if !$0 { session.pendingChannelDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: session.pendingChannelDeletion
        ) { channel in
            Button(L10n.text("channel.delete.action", channel.name), role: .destructive) {
                session.deleteChannel(channel)
            }
        } message: { channel in
            Text(L10n.text("channel.delete.message", channel.name))
        }
    }

    private var emptyTitle: String {
        if case .failed = session.connectionState { return L10n.text("connection.failed") }
        return L10n.text("channels.empty")
    }

    private var emptySymbol: String {
        if case .failed = session.connectionState { return "exclamationmark.triangle" }
        return "waveform"
    }
}

private struct ChannelNode: View {
    @Environment(SessionStore.self) private var session
    let channel: MumbleChannel
    @Binding var highlightedChannelID: MumbleChannel.ID?
    @Binding var highlightedUserID: UInt32?

    var body: some View {
        if channel.children.isEmpty && channel.users.isEmpty {
            ChannelLabel(channel: channel)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(channelHighlight)
                .gesture(channelClickGesture)
                .contextMenu { channelMenu }
                .dropDestination(for: String.self) { items, _ in handleDrop(items) }
        } else {
            DisclosureGroup(isExpanded: Binding(
                get: { session.isChannelExpanded(channel) },
                set: { session.setChannelExpanded(channel, expanded: $0) }
            )) {
                ForEach(channel.users) { user in
                    UserRow(
                        user: user,
                        highlightedUserID: $highlightedUserID,
                        highlightedChannelID: $highlightedChannelID
                    )
                }
                ForEach(channel.children) { child in
                    ChannelNode(
                        channel: child,
                        highlightedChannelID: $highlightedChannelID,
                        highlightedUserID: $highlightedUserID
                    )
                }
            } label: {
                ChannelLabel(channel: channel)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(channelHighlight)
                    .gesture(channelClickGesture)
                    .contextMenu { channelMenu }
                    .dropDestination(for: String.self) { items, _ in handleDrop(items) }
            }
        }
    }

    private var channelHighlight: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                session.selectedChannelID == channel.id
                    ? Color.accentColor.opacity(0.32)
                    : (highlightedChannelID == channel.id ? Color.accentColor.opacity(0.12) : .clear)
            )
    }

    private var channelClickGesture: some Gesture {
        TapGesture(count: 2).exclusively(before: TapGesture(count: 1)).onEnded { click in
            switch click {
            case .first:
                highlightedUserID = nil
                highlightedChannelID = channel.id
                joinChannel()
            case .second:
                highlightedUserID = nil
                highlightedChannelID = channel.id
            }
        }
    }

    private func handleDrop(_ items: [String]) -> Bool {
        guard let payload = items.first else { return false }
        let parts = payload.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let id = UInt32(parts[1]) else { return false }
        if parts[0] == "user", let user = session.flattenedChannels.flatMap(\.users).first(where: { $0.id == id }) {
            session.moveUser(user, to: channel)
            return true
        }
        if parts[0] == "channel", let source = session.flattenedChannels.first(where: { $0.id == id }) {
            session.moveChannel(source, to: channel)
            return true
        }
        return false
    }

    private func joinChannel() {
        guard channel.canEnter else { return }
        session.joinChannel(channel.id)
    }

    @ViewBuilder
    private var channelMenu: some View {
        Button(L10n.text("channel.createSubchannel"), systemImage: "plus") {
            session.channelEditorRequest = ChannelEditorRequest(channel: nil, parentID: channel.id)
        }
        Button(L10n.text("channel.edit"), systemImage: "pencil") {
            session.channelEditorRequest = ChannelEditorRequest(
                channel: channel,
                parentID: channel.parentID ?? channel.id
            )
        }
        Button(
            session.listeningChannelIDs.contains(channel.id)
                ? L10n.text("channel.stopListening")
                : L10n.text("channel.listen"),
            systemImage: session.listeningChannelIDs.contains(channel.id)
                ? "ear.badge.minus"
                : "ear.badge.plus"
        ) {
            session.setChannelListening(
                channel,
                listening: !session.listeningChannelIDs.contains(channel.id)
            )
        }
        Menu(L10n.text("channel.listeningVolume")) {
            ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { volume in
                Button {
                    session.setListeningVolume(volume, for: channel)
                } label: {
                    if session.listeningChannelVolumes[channel.id, default: 1] == volume {
                        Label(percentLabel(volume), systemImage: "checkmark")
                    } else {
                        Text(percentLabel(volume))
                    }
                }
            }
        }
        .disabled(!session.listeningChannelIDs.contains(channel.id))
        Menu(L10n.text("channel.links")) {
            ForEach(session.flattenedChannels.filter { $0.id != channel.id }) { target in
                let linked = channel.linkedChannelIDs.contains(target.id)
                Button {
                    session.setChannelLink(channel, target: target, linked: !linked)
                } label: {
                    if linked { Label(target.name, systemImage: "checkmark") }
                    else { Text(target.name) }
                }
            }
        }
        Button(
            session.pinnedChannelIDs.contains(channel.id) ? L10n.text("channel.unpin") : L10n.text("channel.pin"),
            systemImage: session.pinnedChannelIDs.contains(channel.id) ? "pin.slash" : "pin"
        ) { session.toggleChannelPinned(channel) }
        Button(
            session.hiddenChannelIDs.contains(channel.id) ? L10n.text("channel.unhide") : L10n.text("channel.hide"),
            systemImage: session.hiddenChannelIDs.contains(channel.id) ? "eye" : "eye.slash"
        ) { session.toggleChannelHidden(channel) }
        .disabled(channel.parentID == nil)
        Button(L10n.text("channel.copyURL"), systemImage: "link") {
            session.copyURL(session.channelURL(channel))
        }
        Button(L10n.text("acl.edit"), systemImage: "lock.shield") {
            session.aclEditorChannel = channel
        }
        Menu(L10n.text("voice.setChannelTarget")) {
            Button(L10n.text("voice.channelOnly")) {
                session.setWhisperTarget(channel: channel, links: false, children: false)
            }
            Button(L10n.text("voice.channelAndChildren")) {
                session.setWhisperTarget(channel: channel, links: false, children: true)
            }
            Button(L10n.text("voice.channelLinksChildren")) {
                session.setWhisperTarget(channel: channel, links: true, children: true)
            }
        }
        ForEach(session.contextActions(for: 2)) { action in
            Button(action.title, systemImage: "command") { session.performContextAction(action, channel: channel) }
        }
        Divider()
        Button(L10n.text("common.delete"), systemImage: "trash", role: .destructive) {
            session.pendingChannelDeletion = channel
        }
        .disabled(channel.parentID == nil)
    }

    private func percentLabel(_ volume: Float) -> String {
        L10n.text("user.volume.percent", Int((volume * 100).rounded()))
    }
}

private struct ChannelLabel: View {
    @Environment(SessionStore.self) private var session
    let channel: MumbleChannel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: channel.canEnter ? "waveform.circle" : "lock.circle")
                .foregroundStyle(channel.canEnter ? Color.accentColor : .secondary)
            Text(channel.name)
                .fontWeight(.medium)
            if channel.isTemporary {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if channel.isEnterRestricted {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if session.listeningChannelIDs.contains(channel.id) {
                Image(systemName: "ear.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
            if !channel.linkedChannelIDs.isEmpty {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !channel.users.isEmpty {
                Text("\(channel.users.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .draggable("channel:\(channel.id)")
        .help(channel.descriptionText.isEmpty ? channel.name : MessageText.plainText(from: channel.descriptionText))
        .onHover { hovering in
            if hovering { session.requestChannelDescription(channel) }
        }
    }
}

private struct UserRow: View {
    @Environment(SessionStore.self) private var session
    let user: MumbleUser
    @Binding var highlightedUserID: UInt32?
    @Binding var highlightedChannelID: MumbleChannel.ID?

    private static let volumePresets: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        let isLocallyMuted = session.isLocallyMuted(user)

        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(user.isTalking && !isLocallyMuted ? Color.green : Color.secondary.opacity(0.18))
                    .frame(width: 26, height: 26)
                if let data = user.avatarData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill().clipShape(.circle)
                } else {
                    Text(session.displayName(for: user).prefix(1).uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(user.isTalking && !isLocallyMuted ? .white : .secondary)
                }
            }

            Text(session.displayName(for: user))
                .lineLimit(1)

            Spacer()

            if user.isTalking && !isLocallyMuted {
                Image(systemName: "waveform.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .help(L10n.text("touchBar.speaking", session.displayName(for: user)))
            }
            if user.isSelfMuted || user.isMutedByServer {
                Image(systemName: "mic.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if user.isDeafenedByServer {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if user.isSelfDeafened {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if isLocallyMuted {
                Image(systemName: "speaker.slash.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .help(L10n.text("user.locallyMuted"))
            } else if session.userVolume(user) != 1 {
                Text(L10n.text("user.volume.percent", Int((session.userVolume(user) * 100).rounded())))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if user.isPrioritySpeaker {
                Image(systemName: "star.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .help(L10n.text("user.prioritySpeaker"))
            }
            if session.isFriend(user) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.leading, 20)
        .padding(.vertical, 2)
        .padding(.horizontal, 5)
        .contentShape(.rect)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(highlightedUserID == user.id ? Color.accentColor.opacity(0.12) : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    highlightedUserID == user.id ? Color.accentColor.opacity(0.35) : .clear,
                    lineWidth: 1
                )
        }
        .onTapGesture {
            highlightedChannelID = nil
            highlightedUserID = user.id
        }
        .contextMenu { contextMenu(isLocallyMuted: isLocallyMuted) }
        .draggable("user:\(user.id)")
    }

    @ViewBuilder
    private func contextMenu(isLocallyMuted: Bool) -> some View {
        Button {
            session.privateMessageTarget = user
        } label: {
            Label(L10n.text("user.sendMessage"), systemImage: "bubble.left")
        }


        Button {
            session.showUserInformation(user)
        } label: {
            Label(L10n.text("user.information"), systemImage: "info.circle")
        }
        Button {
            session.jumpToUser(user)
        } label: {
            Label(L10n.text("user.jumpToChannel"), systemImage: "arrow.right.circle")
        }

        Button {
            session.profileEditorTarget = user
            session.requestUserResources(user)
        } label: {
            Label(L10n.text("user.editProfile"), systemImage: "person.text.rectangle")
        }

        Button {
            session.toggleFriend(user)
        } label: {
            Label(
                session.isFriend(user) ? L10n.text("user.friend.remove") : L10n.text("user.friend.add"),
                systemImage: session.isFriend(user) ? "person.badge.minus" : "person.badge.plus"
            )
        }
        .disabled(user.certificateHash == nil)
        Button(session.isIgnoringMessages(from: user) ? L10n.text("user.messages.unignore") : L10n.text("user.messages.ignore")) {
            session.toggleIgnoreMessages(user)
        }
        .disabled(user.certificateHash == nil)
        Button(session.isIgnoringTTS(from: user) ? L10n.text("user.tts.unignore") : L10n.text("user.tts.ignore")) {
            session.toggleIgnoreTTS(user)
        }
        .disabled(user.certificateHash == nil)

        Button {
            session.setWhisperTarget(user: user)
        } label: {
            Label(L10n.text("voice.setUserTarget"), systemImage: "person.wave.2")
        }
        ForEach(session.contextActions(for: 4)) { action in
            Button(action.title, systemImage: "command") { session.performContextAction(action, user: user) }
        }

        Button {
            session.setPrioritySpeaker(!user.isPrioritySpeaker, for: user)
        } label: {
            Label(
                user.isPrioritySpeaker ? L10n.text("user.priority.disable") : L10n.text("user.priority.enable"),
                systemImage: user.isPrioritySpeaker ? "star.slash" : "star"
            )
        }
        if case .connected(let ownSession) = session.connectionState,
           ownSession == user.id, user.registeredUserID == nil {
            Button {
                session.registerUser(user)
            } label: {
                Label(L10n.text("user.register"), systemImage: "person.badge.key")
            }
        }
        Divider()
        Button {
            session.setServerMuted(!user.isMutedByServer, for: user)
        } label: {
            Label(
                user.isMutedByServer ? L10n.text("moderation.serverUnmute") : L10n.text("moderation.serverMute"),
                systemImage: user.isMutedByServer ? "mic" : "mic.slash"
            )
        }
        Button {
            session.setServerDeafened(!user.isDeafenedByServer, for: user)
        } label: {
            Label(
                user.isDeafenedByServer ? L10n.text("moderation.serverUndeafen") : L10n.text("moderation.serverDeafen"),
                systemImage: user.isDeafenedByServer ? "speaker.wave.2" : "speaker.slash"
            )
        }
        Button(L10n.text("moderation.kick.action"), systemImage: "person.crop.circle.badge.xmark") {
            session.moderationRequest = UserModerationRequest(user: user, action: .kick)
        }
        Button(L10n.text("moderation.ban.action"), systemImage: "hand.raised.fill", role: .destructive) {
            session.moderationRequest = UserModerationRequest(user: user, action: .ban)
        }

        Button {
            session.toggleLocalMute(user)
        } label: {
            Label(
                isLocallyMuted ? L10n.text("user.localUnmute") : L10n.text("user.localMute"),
                systemImage: isLocallyMuted ? "speaker.wave.2" : "speaker.slash"
            )
        }

        Menu(L10n.text("user.volume")) {
            ForEach(Self.volumePresets, id: \.self) { preset in
                Button {
                    session.setUserVolume(preset, for: user)
                } label: {
                    if session.userVolume(user) == preset {
                        Label(percentLabel(preset), systemImage: "checkmark")
                    } else {
                        Text(percentLabel(preset))
                    }
                }
            }
        }
        .disabled(isLocallyMuted)
    }

    private func percentLabel(_ gain: Float) -> String {
        L10n.text("user.volume.percent", Int((gain * 100).rounded()))
    }
}

private struct UserInformationView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let user: MumbleUser

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(currentUser.name, systemImage: currentUser.isTalking ? "waveform.circle.fill" : "person.crop.circle")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(currentUser.isTalking ? Color.green : .primary)
                Spacer()
                Button {
                    session.closeUserInformation()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(L10n.text("common.close"))
                .keyboardShortcut(.cancelAction)
            }

            if session.isLoadingUserStatistics {
                ProgressView(L10n.text("user.information.loading"))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let stats = session.userStatistics {
                Form {
                    Section(L10n.text("user.information.client")) {
                        infoRow("user.information.version", value: joined(stats.version, stats.release))
                        infoRow("user.information.system", value: joined(stats.operatingSystem, stats.operatingSystemVersion))
                        infoRow("user.information.opus", value: boolean(stats.supportsOpus))
                        infoRow("user.information.certificate", value: boolean(stats.hasStrongCertificate))
                    }
                    Section(L10n.text("user.information.connection")) {
                        infoRow("user.information.online", value: duration(stats.onlineSeconds))
                        infoRow("user.information.idle", value: duration(stats.idleSeconds))
                        infoRow("user.information.bandwidth", value: bandwidth(stats.bandwidth))
                        infoRow("user.information.tcp", value: L10n.text("user.information.transport", stats.tcpPackets, stats.tcpPingMilliseconds))
                        infoRow("user.information.udp", value: L10n.text("user.information.transport", stats.udpPackets, stats.udpPingMilliseconds))
                    }
                    if let received = stats.fromClient, let sent = stats.fromServer {
                        Section(L10n.text("user.information.packets")) {
                            packetRow("user.information.received", stats: received)
                            packetRow("user.information.sent", stats: sent)
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView(L10n.text("user.information.unavailable"), systemImage: "info.circle")
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
        .task {
            while !Task.isCancelled, session.userInformationTarget?.id == user.id {
                session.refreshUserInformation()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onDisappear { session.closeUserInformation() }
    }

    private var currentUser: MumbleUser {
        session.currentUser(sessionID: user.id) ?? user
    }

    private func infoRow(_ key: String, value: String) -> some View {
        LabeledContent(L10n.text(key), value: value)
    }

    private func packetRow(_ key: String, stats: MumblePacketStatistics) -> some View {
        LabeledContent(
            L10n.text(key),
            value: L10n.text("user.information.packetSummary", stats.good, stats.late, stats.lost, stats.lossPercent)
        )
    }

    private func joined(_ first: String?, _ second: String?) -> String {
        [first, second].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty
            ?? L10n.text("user.information.unavailableValue")
    }

    private func boolean(_ value: Bool?) -> String {
        guard let value else { return L10n.text("user.information.unavailableValue") }
        return value ? L10n.text("common.yes") : L10n.text("common.no")
    }

    private func duration(_ seconds: UInt32?) -> String {
        guard let seconds else { return L10n.text("user.information.unavailableValue") }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.day, .hour, .minute] : [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)s"
    }

    private func bandwidth(_ value: UInt32?) -> String {
        guard let value else { return L10n.text("user.information.unavailableValue") }
        return L10n.text("user.information.bandwidthValue", Double(value) / 125)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct PrivateMessageComposer: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let user: MumbleUser
    @State private var draft = ""
    @State private var editorHeight: CGFloat = 68
    @State private var isComposing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.text("chat.privateTo", user.name), systemImage: "lock.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.purple)

            ZStack(alignment: .topLeading) {
                if draft.isEmpty && !isComposing {
                    Text(L10n.text("chat.placeholder"))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
                NativeTextEditor(
                    text: $draft,
                    contentHeight: $editorHeight,
                    maximumHeight: 132,
                    onCompositionChange: { isComposing = $0 }
                )
            }
                .frame(height: max(68, editorHeight))
                .padding(10)
                .nativeGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Spacer()
                Button(L10n.text("common.cancel"), role: .cancel) { dismiss() }
                Button(L10n.text("chat.send")) {
                    session.sendPrivateMessage(draft, to: user)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
