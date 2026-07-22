import AppKit
import Foundation
import MumbleAudio
import MumbleProtocol
import MumbleSystem
extension SessionStore {
    var selectedServer: MumbleServer? {
        serverRepository.selectedServer
    }

    var activeServer: MumbleServer? {
        serverRepository.activeServer
    }

    var ownUser: MumbleUser? {
        guard case .connected(let sessionID) = connectionState else { return nil }
        return findUser(session: sessionID, in: channels)
    }

    var isServerOwner: Bool {
        ownUser?.isSuperUser == true
    }

    func hasPermission(_ permission: MumblePermission) -> Bool {
        isServerOwner || currentPermissions.contains(permission)
    }

    var hasUserManagementPermission: Bool {
        [.write, .muteDeafen, .kick, .ban].contains(where: hasPermission)
    }

    func selectServer(_ server: MumbleServer) {
        if serverRepository.select(server.id) { selectedServerDidChange() }
    }

    func connect(to server: MumbleServer, password: String? = nil) {
        if let activeServerID, activeServerID != server.id {
            prepareLocalDisconnect()
        }
        if serverRepository.forceSelect(server.id) { selectedServerDidChange() }
        connect(password: password)
    }

    func hasActiveSession(for server: MumbleServer) -> Bool {
        activeServerID == server.id && connectionState != .disconnected
    }

    func canUseServerSessionActions(for server: MumbleServer) -> Bool {
        guard activeServerID == server.id else { return false }
        if case .connected = connectionState { return true }
        return false
    }

    func selectedServerDidChange() {
        loadChannelPreferences()
        applyShortcutConfigurationForSelectedServer()
    }

    var selectedServerUsesShortcutOverride: Bool {
        shortcuts.usesOverride(for: selectedServerID)
    }

    var editingServer: MumbleServer? {
        guard let editingServerID else { return nil }
        return servers.first { $0.id == editingServerID }
    }

    var selectedChannel: MumbleChannel? {
        guard let selectedChannelID else { return nil }
        return findChannel(id: selectedChannelID, in: channels)
    }

    var flattenedChannels: [MumbleChannel] {
        flattenChannels(channels)
    }

    var talkingUserNames: [String] {
        flattenedChannels
            .flatMap(\.users)
            .filter { talkingSessions.contains($0.id) }
            .map(displayName(for:))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Live speaking state for a user, driven by the observed `talkingSessions`
    /// set rather than the (structural) channel tree.
    func isTalking(_ user: MumbleUser) -> Bool {
        talkingSessions.contains(user.id)
    }

    var visibleChannels: [MumbleChannel] {
        let required = requiredVisibleChannelIDs
        let filtered = channels.compactMap { filterChannel($0, required: required) }
        return filtered.sorted { lhs, rhs in
            let lhsPinned = pinnedChannelIDs.contains(lhs.id)
            let rhsPinned = pinnedChannelIDs.contains(rhs.id)
            return lhsPinned == rhsPinned ? channelSort(lhs, rhs) : lhsPinned
        }
    }

    func setHideEmptyChannels(_ hidden: Bool) {
        hideEmptyChannels = hidden
        UserDefaults.standard.set(hidden, forKey: "hideEmptyChannels")
    }

    func setShowsReturnToPreviousChannelControl(_ visible: Bool) {
        showsReturnToPreviousChannelControl = visible
        UserDefaults.standard.set(visible, forKey: "showsReturnToPreviousChannelControl")
    }

    func setShowsHideEmptyChannelsControl(_ visible: Bool) {
        showsHideEmptyChannelsControl = visible
        UserDefaults.standard.set(visible, forKey: "showsHideEmptyChannelsControl")
        if !visible { setHideEmptyChannels(false) }
    }

    func toggleChannelHidden(_ channel: MumbleChannel) {
        if hiddenChannelIDs.remove(channel.id) == nil { hiddenChannelIDs.insert(channel.id) }
        persistChannelPreferences()
    }

    func toggleChannelPinned(_ channel: MumbleChannel) {
        if pinnedChannelIDs.remove(channel.id) == nil { pinnedChannelIDs.insert(channel.id) }
        persistChannelPreferences()
    }
    func isChannelExpanded(_ channel: MumbleChannel) -> Bool { expandedChannelIDs.contains(channel.id) }
    func setChannelExpanded(_ channel: MumbleChannel, expanded: Bool) {
        if expanded { expandedChannelIDs.insert(channel.id) } else { expandedChannelIDs.remove(channel.id) }
    }
    func setChannelExpansionPolicy(_ policy: ChannelExpansionPolicy) {
        channelExpansionPolicy = policy; UserDefaults.standard.set(policy.rawValue, forKey: "channelExpansionPolicy")
        applyChannelExpansionPolicy()
    }
    func applyChannelExpansionPolicy() {
        switch channelExpansionPolicy {
        case .all: expandedChannelIDs = Set(flattenedChannels.map(\.id))
        case .collapsed: expandedChannelIDs = Set(channels.map(\.id))
        case .currentPath:
            let ownChannel: UInt32?
            if case .connected(let session) = connectionState {
                ownChannel = flattenedChannels.flatMap(\.users).first { $0.id == session }?.channelID
            } else { ownChannel = nil }
            let target = selectedChannelID ?? ownChannel
            guard let target else { return }
            expandedChannelIDs = requiredVisibleChannelIDs.union([target])
        }
    }

    func jumpToUser(_ user: MumbleUser) {
        selectedChannelID = user.channelID
        var current = flattenedChannels.first { $0.id == user.channelID }
        while let channel = current {
            expandedChannelIDs.insert(channel.id)
            current = channel.parentID.flatMap { id in flattenedChannels.first { $0.id == id } }
        }
    }

    func moveUser(_ user: MumbleUser, to channel: MumbleChannel) { sendMoveUser(user.id, to: channel.id) }

    func moveChannel(_ channel: MumbleChannel, to parent: MumbleChannel) {
        guard channel.id != parent.id, channel.parentID != nil,
              !descendantIDs(of: channel).contains(parent.id) else { return }
        Task { try? await controlConnection.send(MumbleCommands.moveChannel(channelID: channel.id, toParent: parent.id)) }
    }

    func sendMoveUser(_ session: UInt32, to channelID: UInt32) {
        guard case .connected = connectionState else { return }
        Task { try? await controlConnection.send(MumbleCommands.moveUser(session: session, toChannel: channelID)) }
    }

    var channelPreferencePrefix: String {
        "channelPreferences.\((activeServerID ?? selectedServerID)?.uuidString ?? "none")"
    }

    func persistChannelPreferences() {
        UserDefaults.standard.set(hiddenChannelIDs.map(String.init), forKey: "\(channelPreferencePrefix).hidden")
        UserDefaults.standard.set(pinnedChannelIDs.map(String.init), forKey: "\(channelPreferencePrefix).pinned")
    }

    func loadChannelPreferences() {
        let defaults = UserDefaults.standard
        hiddenChannelIDs = Set((defaults.stringArray(forKey: "\(channelPreferencePrefix).hidden") ?? []).compactMap(UInt32.init))
        pinnedChannelIDs = Set((defaults.stringArray(forKey: "\(channelPreferencePrefix).pinned") ?? []).compactMap(UInt32.init))
    }

    var requiredVisibleChannelIDs: Set<UInt32> {
        var required = Set(listeningChannelIDs).union(pinnedChannelIDs)
        if let selectedChannelID { required.insert(selectedChannelID) }
        if case .connected(let session) = connectionState,
           let own = flattenedChannels.flatMap(\.users).first(where: { $0.id == session }) { required.insert(own.channelID) }
        var result = required
        for id in required {
            var current = flattenedChannels.first { $0.id == id }
            while let parent = current?.parentID {
                result.insert(parent)
                current = flattenedChannels.first { $0.id == parent }
            }
        }
        return result
    }

    func filterChannel(_ channel: MumbleChannel, required: Set<UInt32>) -> MumbleChannel? {
        var copy = channel
        copy.children = channel.children.compactMap { filterChannel($0, required: required) }
            .sorted(by: channelSort)
        let explicitlyHidden = hiddenChannelIDs.contains(channel.id) && !required.contains(channel.id)
        let empty = channel.users.isEmpty && copy.children.isEmpty
        if explicitlyHidden || (hideEmptyChannels && empty && !required.contains(channel.id) && channel.parentID != nil) { return nil }
        return copy
    }

    func channelSort(_ lhs: MumbleChannel, _ rhs: MumbleChannel) -> Bool {
        lhs.position == rhs.position
            ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            : lhs.position < rhs.position
    }

    func descendantIDs(of channel: MumbleChannel) -> Set<UInt32> {
        Set(flattenChannels(channel.children).map(\.id))
    }
}
