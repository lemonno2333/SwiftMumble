import Foundation
import MumbleSystem
import Testing

private func configuration(label: String) -> ServerShortcutConfiguration {
    let shortcut = GlobalHotKeyShortcut(keyCode: 1, keyLabel: label, control: true)
    return ServerShortcutConfiguration(
        pushToTalk: shortcut,
        pushToMute: shortcut,
        audio: [.toggleMute: shortcut],
        whisper: shortcut
    )
}

@Test func serverShortcutProfilesUseGlobalFallbackAndOverride() {
    let serverID = UUID()
    let global = configuration(label: "Global")
    let local = configuration(label: "Server")
    var profiles = ServerShortcutProfiles(global: global)

    #expect(profiles.configuration(serverID: serverID) == global)
    profiles.setOverride(local, serverID: serverID)
    #expect(profiles.configuration(serverID: serverID) == local)
    profiles.setOverride(nil, serverID: serverID)
    #expect(profiles.configuration(serverID: serverID) == global)
}

@Test func serverShortcutProfilesRoundTripThroughPersistence() throws {
    let serverID = UUID()
    var profiles = ServerShortcutProfiles(global: configuration(label: "Global"))
    profiles.setOverride(configuration(label: "Server"), serverID: serverID)

    let data = try JSONEncoder().encode(profiles)
    let restored = try JSONDecoder().decode(ServerShortcutProfiles.self, from: data)

    #expect(restored == profiles)
    #expect(restored.configuration(serverID: serverID).pushToTalk.keyLabel == "Server")
}
