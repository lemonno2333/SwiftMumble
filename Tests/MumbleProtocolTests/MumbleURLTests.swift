import Foundation
import Testing
@testable import MumbleProtocol

@Test func mumbleURLRoundTripsServerAndChannelPath() throws {
    let value = MumbleURL(host: "voice.example.com", port: 64739, username: "Alice", channelPath: ["Games", "Team A"])
    let url = try #require(value.url)
    let parsed = try #require(MumbleURL(url: url))
    #expect(parsed == value)
}

@Test func mumbleURLUsesDefaultPort() throws {
    let parsed = try #require(MumbleURL(url: URL(string: "mumble://example.com/Lobby")!))
    #expect(parsed.port == 64738)
    #expect(parsed.channelPath == ["Lobby"])
}
