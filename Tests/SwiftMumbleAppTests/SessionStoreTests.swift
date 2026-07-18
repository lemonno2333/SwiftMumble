import MumbleProtocol
import Testing
@testable import SwiftMumbleApp

@MainActor
@Test func activeSessionPreventsSidebarSelectionFromChangingServers() {
    let first = MumbleServer(name: "First", host: "first.example")
    let second = MumbleServer(name: "Second", host: "second.example")
    let session = SessionStore(
        servers: [first, second],
        connectionState: .connected(session: 1),
        activeServerID: first.id,
        performStartup: false
    )

    session.selectServer(second)

    #expect(session.selectedServerID == first.id)
    #expect(session.activeServerID == first.id)
    #expect(session.activeServer?.host == "first.example")
}

@MainActor
@Test func disconnectedSessionAllowsSelectingAnotherServer() {
    let first = MumbleServer(name: "First", host: "first.example")
    let second = MumbleServer(name: "Second", host: "second.example")
    let session = SessionStore(servers: [first, second], performStartup: false)

    session.selectServer(second)

    #expect(session.selectedServerID == second.id)
}

@MainActor
@Test func chatDraftIsPreservedWhenConnectionIsNotReady() {
    let channel = MumbleChannel(id: 1, name: "Lobby")
    let session = SessionStore(channels: [channel], connectionState: .failed(message: "offline"), performStartup: false)
    session.chat.draft = "message to keep"

    session.sendChatMessage()

    #expect(session.chat.draft == "message to keep")
    #expect(session.serverManagementError != nil)
}
