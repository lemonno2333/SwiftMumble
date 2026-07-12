import Testing
@testable import MumbleProtocol

@Test func handshakeUsesUpstreamVersionEncodingAndOpus() throws {
    let frames = try MumbleHandshake.frames(
        credentials: MumbleCredentials(username: "Leo", password: "secret", tokens: ["dev"]),
        operatingSystemVersion: "26.0"
    )

    #expect(frames.map(\.type) == [.version, .authenticate])

    let version = try frames[0].decode(as: MumbleProto_Version.self)
    #expect(version.versionV1 == 0x010700)
    #expect(version.versionV2 == 0x0001_0007_0000_0000)
    #expect(version.os == "macOS")

    let authentication = try frames[1].decode(as: MumbleProto_Authenticate.self)
    #expect(authentication.username == "Leo")
    #expect(authentication.password == "secret")
    #expect(authentication.tokens == ["dev"])
    #expect(authentication.opus)
}
