import AppKit
import Foundation
import MumbleAudio
import MumbleProtocol
import MumbleSystem
extension SessionStore {
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
                handleCommandSendFailure(L10n.text("channel.joinError", error.localizedDescription))
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
        let text = chat.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let selectedChannelID else { return }
        guard case .connected = connectionState else {
            serverManagementError = L10n.text("chat.notConnected")
            return
        }
        guard text.utf8.count <= (text.contains("<img") ? serverImageMessageLengthLimit : serverMessageLengthLimit) else {
            serverManagementError = L10n.text("chat.tooLong")
            return
        }
        chat.acceptOutgoing(text)

        Task {
            do {
                try await controlConnection.send(MumbleCommands.sendText(text, toChannel: selectedChannelID))
                chat.append(
                    ChatEntry(author: L10n.text("chat.you"), timestamp: Date(), text: text, isLocal: true)
                )
            } catch {
                chat.restoreDraftIfEmpty(text)
                handleCommandSendFailure(L10n.text("chat.sendError", error.localizedDescription))
            }
        }
    }

    func navigateChatHistory(older: Bool) {
        chat.navigateHistory(older: older)
    }

    func completeChatUsername() {
        let names = flattenedChannels.flatMap(\.users).map { displayName(for: $0) }
        chat.completeUsername(candidates: names)
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
        chat.appendToDraft(html)
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
                chat.append(
                    ChatEntry(
                        author: L10n.text("chat.privateTo", recipient),
                        timestamp: Date(),
                        text: trimmed,
                        isLocal: true,
                        isPrivate: true
                    )
                )
            } catch {
                handleCommandSendFailure(L10n.text("chat.sendError", error.localizedDescription))
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

    func sendServerAudioState(_ user: MumbleUser, muted: Bool?, deafened: Bool?) {
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

    func requestUserStatistics(sessionID: UInt32) {
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
                handleCommandSendFailure(L10n.text("channel.joinError", error.localizedDescription))
            }
        }
    }

    var canReturnToPreviousChannel: Bool {
        guard case .connected = connectionState else { return false }
        return channelHistory.previousChannelID != nil
    }

    func trackOwnChannel(_ channelID: MumbleChannel.ID) {
        _ = channelHistory.observe(channelID: channelID)
        selectedChannelID = channelID
        expandChannelPath(to: channelID)
    }

    func expandChannelPath(to channelID: MumbleChannel.ID) {
        var current = flattenedChannels.first { $0.id == channelID }
        while let channel = current {
            expandedChannelIDs.insert(channel.id)
            current = channel.parentID.flatMap { parentID in
                flattenedChannels.first { $0.id == parentID }
            }
        }
    }
}
