import Foundation

public struct MumbleProtocolVersion: Equatable, Sendable {
    public let major: UInt16
    public let minor: UInt16
    public let patch: UInt16

    public init(major: UInt16, minor: UInt16, patch: UInt16) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var versionV2: UInt64 {
        UInt64(major) << 48 | UInt64(minor) << 32 | UInt64(patch) << 16
    }

    public var legacyVersion: UInt32 {
        UInt32(min(major, 255)) << 16
            | UInt32(min(minor, 255)) << 8
            | UInt32(min(patch, 255))
    }

    public static let current = MumbleProtocolVersion(major: 1, minor: 7, patch: 0)
    public static let protobufAudioIntroduction = MumbleProtocolVersion(major: 1, minor: 5, patch: 0)

    public var usesProtobufAudio: Bool {
        versionV2 >= Self.protobufAudioIntroduction.versionV2
    }

    public init(message: MumbleProto_Version) {
        if message.hasVersionV2 {
            major = UInt16((message.versionV2 >> 48) & 0xffff)
            minor = UInt16((message.versionV2 >> 32) & 0xffff)
            patch = UInt16((message.versionV2 >> 16) & 0xffff)
        } else {
            major = UInt16((message.versionV1 >> 16) & 0xff)
            minor = UInt16((message.versionV1 >> 8) & 0xff)
            patch = UInt16(message.versionV1 & 0xff)
        }
    }
}

public struct MumbleCredentials: Equatable, Sendable {
    public var username: String
    public var password: String
    public var tokens: [String]

    public init(username: String, password: String = "", tokens: [String] = []) {
        self.username = username
        self.password = password
        self.tokens = tokens
    }
}

public enum MumbleHandshake {
    public static func frames(
        credentials: MumbleCredentials,
        release: String = "SwiftMumble 0.1.0",
        protocolVersion: MumbleProtocolVersion = .current,
        operatingSystem: String = "macOS",
        operatingSystemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) throws -> [MumbleFrame] {
        var version = MumbleProto_Version()
        version.versionV1 = protocolVersion.legacyVersion
        version.versionV2 = protocolVersion.versionV2
        version.release = release
        version.os = operatingSystem
        version.osVersion = operatingSystemVersion

        var authenticate = MumbleProto_Authenticate()
        authenticate.username = credentials.username
        if !credentials.password.isEmpty {
            authenticate.password = credentials.password
        }
        authenticate.tokens = credentials.tokens
        authenticate.opus = true

        return [
            try MumbleFrame(type: .version, message: version),
            try MumbleFrame(type: .authenticate, message: authenticate)
        ]
    }
}
