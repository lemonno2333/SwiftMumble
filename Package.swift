// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SwiftMumble",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MumbleProtocol", targets: ["MumbleProtocol"]),
        .library(name: "MumbleAudio", targets: ["MumbleAudio"]),
        .library(name: "MumbleSystem", targets: ["MumbleSystem"]),
        .executable(name: "SwiftMumble", targets: ["SwiftMumbleApp"]),
        .executable(name: "MumbleProbe", targets: ["MumbleProbe"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            exact: "1.38.1"
        ),
        .package(
            url: "https://github.com/ddddxxx/TouchBarHelper.git",
            exact: "0.1.0"
        ),
        .package(
            url: "https://github.com/scinfu/SwiftSoup.git",
            exact: "2.9.6"
        ),
        .package(
            url: "https://github.com/sindresorhus/KeyboardShortcuts.git",
            exact: "3.0.1"
        ),
        .package(
            url: "https://github.com/apple/swift-certificates.git",
            exact: "1.19.3"
        )
    ],
    targets: [
        .target(
            name: "MumbleProtocol",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ]
        ),
        .binaryTarget(
            name: "COpus",
            path: "Vendor/Opus/Opus.xcframework"
        ),
        .binaryTarget(
            name: "CRNNoise",
            path: "Vendor/RNNoise/RNNoise.xcframework"
        ),
        .target(
            name: "COpusShim",
            dependencies: ["COpus"]
        ),
        .target(
            name: "MumbleAudio",
            dependencies: ["COpus", "COpusShim", "CRNNoise"]
        ),
        .target(
            name: "MumbleSystem",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "X509", package: "swift-certificates")
            ]
        ),
        .executableTarget(
            name: "SwiftMumbleApp",
            dependencies: [
                "MumbleProtocol", "MumbleAudio", "MumbleSystem",
                .product(name: "TouchBarHelper", package: "TouchBarHelper"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "MumbleProbe",
            dependencies: ["MumbleProtocol", "MumbleAudio"]
        ),
        .testTarget(
            name: "MumbleProtocolTests",
            dependencies: ["MumbleProtocol"]
        ),
        .testTarget(
            name: "MumbleAudioTests",
            dependencies: ["MumbleAudio"]
        ),
        .testTarget(
            name: "MumbleSystemTests",
            dependencies: ["MumbleSystem"]
        ),
        .testTarget(
            name: "SwiftMumbleAppTests",
            dependencies: ["SwiftMumbleApp"]
        )
    ]
)
