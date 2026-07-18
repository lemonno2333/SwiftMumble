import AppKit
import Foundation
import MumbleAudio
import MumbleProtocol
import MumbleSystem
extension SessionStore {
    func contextActions(for context: UInt32) -> [ServerContextAction] {
        serverContextActions.filter { $0.contexts & context != 0 }
    }

    func performContextAction(_ action: ServerContextAction, user: MumbleUser? = nil, channel: MumbleChannel? = nil) {
        Task { do { try await controlConnection.send(MumbleCommands.performContextAction(
            action.action, session: user?.id, channelID: channel?.id
        )) } catch { serverManagementError = error.localizedDescription } }
    }

    func flattenChannels(_ channels: [MumbleChannel]) -> [MumbleChannel] {
        channels.flatMap { [$0] + flattenChannels($0.children) }
    }

    func userName(session: UInt32) -> String {
        findUser(session: session, in: channels)?.name ?? L10n.text("user.unknown", session)
    }

    func notifyUserChanges(
        from oldChannels: [MumbleChannel],
        to newChannels: [MumbleChannel],
        ownSession: UInt32?
    ) {
        let oldUsers = Dictionary(uniqueKeysWithValues: allUsers(in: oldChannels).map { ($0.id, $0) })
        let newUsers = Dictionary(uniqueKeysWithValues: allUsers(in: newChannels).map { ($0.id, $0) })
        for user in newUsers.values where oldUsers[user.id] == nil && user.id != ownSession {
            if notificationsEnabled { MumbleNotificationService.post(title: L10n.text("notifications.userJoined.title"), body: user.name) }
            if audioCuesEnabled { playAudioCue(.userJoined) }
        }
        for user in oldUsers.values where newUsers[user.id] == nil && user.id != ownSession {
            if notificationsEnabled { MumbleNotificationService.post(title: L10n.text("notifications.userLeft.title"), body: user.name) }
            if audioCuesEnabled { playAudioCue(.userLeft) }
        }
    }

    func setChatLogLimit(_ limit: Int) {
        chat.setLogLimit(limit)
    }
    func setChatUses24HourTime(_ enabled: Bool) {
        chat.setUses24HourTime(enabled)
    }
    func formattedChatTime(_ date: Date) -> String {
        chat.formattedTime(date)
    }

    func allUsers(in channels: [MumbleChannel]) -> [MumbleUser] {
        channels.flatMap { $0.users + allUsers(in: $0.children) }
    }

    func findUser(session: UInt32, in channels: [MumbleChannel]) -> MumbleUser? {
        for channel in channels {
            if let user = channel.users.first(where: { $0.id == session }) { return user }
            if let user = findUser(session: session, in: channel.children) { return user }
        }
        return nil
    }
}
