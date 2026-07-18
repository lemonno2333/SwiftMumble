import AppKit
import Foundation
import MumbleAudio
import MumbleProtocol
import MumbleSystem
extension SessionStore {
    static let preview: SessionStore = {
        let loungeUsers = [
            MumbleUser(id: 1, name: "Leo", channelID: 1, isTalking: true),
            MumbleUser(id: 2, name: "Mina", channelID: 1),
            MumbleUser(id: 3, name: "Alex", channelID: 1, isSelfMuted: true)
        ]
        let projectUsers = [
            MumbleUser(id: 4, name: "Sam", channelID: 2),
            MumbleUser(id: 5, name: "Riley", channelID: 2)
        ]
        let channels = [
            MumbleChannel(
                id: 0,
                name: "Root",
                children: [
                    MumbleChannel(id: 1, parentID: 0, name: "Lounge", users: loungeUsers),
                    MumbleChannel(id: 2, parentID: 0, name: "Project Room", users: projectUsers),
                    MumbleChannel(id: 3, parentID: 0, name: "Quiet Corner")
                ]
            )
        ]
        return SessionStore(
            servers: [
                MumbleServer(name: "Community", host: "voice.example.net", username: "Leo", isFavorite: true),
                MumbleServer(name: "Local Server", host: "localhost", username: "Leo")
            ],
            channels: channels,
            connectionState: .connected(session: 1)
        )
    }()
}
