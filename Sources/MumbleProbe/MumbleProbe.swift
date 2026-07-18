import Darwin
import Foundation
import MumbleAudio
import MumbleProtocol

@main
struct MumbleProbe {
    static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count >= 4 else {
            print("Usage: MumbleProbe <host> <username> <sha256-certificate-fingerprint|-> [port]")
            exit(2)
        }

        let host = arguments[1]
        let username = arguments[2]
        let fingerprint = arguments[3] == "-" ? nil : MumbleCertificateFingerprint(hex: arguments[3])
        if arguments[3] != "-", fingerprint == nil {
            print("Invalid SHA-256 certificate fingerprint")
            exit(2)
        }
        let port = arguments.dropFirst(4).compactMap(UInt16.init).first ?? 64738
        let shouldTestAudioLoopback = arguments.contains("--audio-loopback")
        let shouldTestUDPLoopback = arguments.contains("--udp-loopback")
        let connection = MumbleControlConnection()
        let stream = await connection.connect(
            host: host,
            port: port,
            pinnedCertificateSHA256: fingerprint?.bytes
        )

        let timeout = Task {
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            print("Timed out waiting for ServerSync")
            await connection.disconnect()
        }

        var state = MumbleServerState()
        var succeeded = false
        var loopbackDecoder: OpusDecoder?
        var serverProtocolVersion = MumbleProtocolVersion(major: 1, minor: 4, patch: 0)
        var udpTask: Task<Void, Never>?
        let probeStatus = ProbeStatus()

        for await event in stream {
            switch event {
            case .preparing:
                print("Preparing TLS connection...")

            case .ready:
                print("TLS ready; sending Mumble handshake")
                do {
                    for frame in try MumbleHandshake.frames(
                        credentials: MumbleCredentials(username: username)
                    ) {
                        try await connection.send(frame)
                    }
                } catch {
                    print("Handshake failed: \(error)")
                    await connection.disconnect()
                }

            case .frame(let frame):
                if frame.type == .version {
                    if let versionMessage = try? frame.decode(as: MumbleProto_Version.self) {
                        serverProtocolVersion = MumbleProtocolVersion(message: versionMessage)
                        print(
                            "Server version: \(serverProtocolVersion.major)."
                                + "\(serverProtocolVersion.minor).\(serverProtocolVersion.patch)"
                        )
                    }
                    continue
                }

                if frame.type == .cryptSetup, shouldTestUDPLoopback {
                    do {
                        let setup = try frame.decode(as: MumbleProto_CryptSetup.self)
                        if setup.hasKey, setup.hasClientNonce, setup.hasServerNonce {
                            let cryptState = try MumbleCryptState(
                                key: setup.key,
                                clientNonce: setup.clientNonce,
                                serverNonce: setup.serverNonce
                            )
                            let udpConnection = MumbleUDPConnection(cryptState: cryptState)
                            let host = host
                            let version = serverProtocolVersion
                            udpTask = Task {
                                let udpEvents = await udpConnection.connect(host: host, port: port)
                                let pingTimestamp = UInt64(Date().timeIntervalSince1970 * 1_000)
                                var sentLoopback = false
                                let decoder = try? OpusDecoder()

                                for await udpEvent in udpEvents {
                                    switch udpEvent {
                                    case .ready:
                                        do {
                                            try await udpConnection.send(
                                                MumbleUDPPacket.ping(
                                                    timestamp: pingTimestamp,
                                                    protocolVersion: version
                                                )
                                            )
                                            print("Encrypted UDP ping sent")
                                        } catch {
                                            print("UDP ping send failed: \(error)")
                                        }

                                    case .packet(let packet):
                                        if let timestamp = try? MumbleUDPPacket.pingTimestamp(
                                            from: packet,
                                            protocolVersion: version
                                        ), timestamp == pingTimestamp, !sentLoopback {
                                            print("Encrypted UDP ping received")
                                            sentLoopback = true
                                            do {
                                                try await sendAudioLoopback(
                                                    on: udpConnection,
                                                    protocolVersion: version
                                                )
                                                print("Audio loopback sent through encrypted UDP")
                                            } catch {
                                                print("UDP audio send failed: \(error)")
                                            }
                                        } else if sentLoopback, let decoder {
                                            do {
                                                let audio = try MumbleVoicePacket.decodeTunneledAudio(
                                                    MumbleFrame(type: .udpTunnel, payload: packet)
                                                )
                                                if !audio.opusData.isEmpty {
                                                    let samples = try decoder.decode(packet: audio.opusData)
                                                    print(
                                                        "UDP audio loopback received: frame=\(audio.frameNumber), "
                                                            + "samples=\(samples.count)"
                                                    )
                                                    await probeStatus.markSucceeded()
                                                    timeout.cancel()
                                                    await udpConnection.disconnect()
                                                    await connection.disconnect()
                                                }
                                            } catch {
                                                print("UDP audio decode failed: \(error)")
                                            }
                                        }

                                    case .failed(let message):
                                        print("UDP failed: \(message)")
                                    case .disconnected:
                                        break
                                    }
                                }
                            }
                        }
                    } catch {
                        print("CryptSetup failed: \(error)")
                    }
                    continue
                }

                if frame.type == .udpTunnel, shouldTestAudioLoopback {
                    do {
                        let audio = try MumbleVoicePacket.decodeTunneledAudio(frame)
                        if !audio.opusData.isEmpty {
                            let decoder = try loopbackDecoder ?? OpusDecoder()
                            loopbackDecoder = decoder
                            let samples = try decoder.decode(packet: audio.opusData)
                            print("Audio loopback received: frame=\(audio.frameNumber), samples=\(samples.count)")
                            succeeded = samples.count == 480
                            timeout.cancel()
                            await connection.disconnect()
                        }
                    } catch {
                        print("Audio loopback decode failed: \(error)")
                        await connection.disconnect()
                    }
                    continue
                }

                if frame.type == .reject {
                    if let rejection = try? frame.decode(as: MumbleProto_Reject.self) {
                        print("Rejected: \(rejection.reason)")
                    }
                    await connection.disconnect()
                    continue
                }

                do {
                    let change = try state.apply(frame)
                    if case .synchronized(let session) = change {
                        let snapshot = state.snapshot()
                        print("ServerSync session=\(session)")
                        if !snapshot.welcomeText.isEmpty {
                            print("Welcome: \(snapshot.welcomeText)")
                        }
                        print("Channels:")
                        printChannels(snapshot.channels)
                        if shouldTestUDPLoopback {
                            print("Waiting for encrypted UDP validation")
                        } else if shouldTestAudioLoopback {
                            do {
                                try await sendAudioLoopback(
                                    on: connection,
                                    protocolVersion: serverProtocolVersion
                                )
                            } catch {
                                print("Audio loopback send failed: \(error)")
                                await connection.disconnect()
                            }
                        } else {
                            succeeded = true
                            timeout.cancel()
                            await connection.disconnect()
                        }
                    }
                } catch {
                    print("Protocol error for \(frame.type): \(error)")
                    await connection.disconnect()
                }

            case .waiting(let message):
                print("Waiting: \(message)")
            case .untrustedCertificate(let subject, let fingerprint):
                print("Untrusted certificate: \(subject) \(fingerprint.formatted)")
                await connection.disconnect()
            case .certificateMismatch(let subject, let expected, let actual):
                print(
                    "Certificate mismatch: \(subject) expected=\(expected.formatted) actual=\(actual.formatted)"
                )
                await connection.disconnect()
            case .failed(let message):
                print("Connection failed: \(message)")
            case .disconnected:
                break
            }
        }

        timeout.cancel()
        udpTask?.cancel()
        if await probeStatus.succeeded { succeeded = true }
        exit(succeeded ? 0 : 1)
    }

    private static func printChannels(_ channels: [MumbleChannel], depth: Int = 0) {
        for channel in channels {
            let indent = String(repeating: "  ", count: depth)
            print("\(indent)- \(channel.name) [id=\(channel.id), users=\(channel.users.count)]")
            for user in channel.users {
                print("\(indent)  * \(user.name) [session=\(user.id)]")
            }
            printChannels(channel.children, depth: depth + 1)
        }
    }

    private static func sendAudioLoopback(
        on connection: MumbleControlConnection,
        protocolVersion: MumbleProtocolVersion
    ) async throws {
        let pipeline = try AudioTransmitPipeline()
        for frameIndex in 0..<8 {
            let samples = (0..<480).map { sampleIndex in
                let absoluteIndex = frameIndex * 480 + sampleIndex
                return Float(sin(2 * Double.pi * 440 * Double(absoluteIndex) / 48_000)) * 0.05
            }
            let encoded = try pipeline.encode(samples: samples)
            try await connection.send(
                MumbleVoicePacket.tunnelClientAudio(
                    opusData: encoded.opusData,
                    frameNumber: encoded.frameNumber,
                    target: 31,
                    protocolVersion: protocolVersion
                )
            )
        }

        try await connection.send(
            MumbleVoicePacket.tunnelClientAudio(
                opusData: Data(),
                frameNumber: pipeline.takeTerminatorFrameNumber(),
                target: 31,
                isTerminator: true,
                protocolVersion: protocolVersion
            )
        )
        print("Audio loopback sent through TCP tunnel")
    }

    private static func sendAudioLoopback(
        on connection: MumbleUDPConnection,
        protocolVersion: MumbleProtocolVersion
    ) async throws {
        let pipeline = try AudioTransmitPipeline()
        for frameIndex in 0..<8 {
            let samples = (0..<480).map { sampleIndex in
                let absoluteIndex = frameIndex * 480 + sampleIndex
                return Float(sin(2 * Double.pi * 440 * Double(absoluteIndex) / 48_000)) * 0.05
            }
            let encoded = try pipeline.encode(samples: samples)
            try await connection.send(
                MumbleVoicePacket.clientAudioPacket(
                    opusData: encoded.opusData,
                    frameNumber: encoded.frameNumber,
                    target: 31,
                    protocolVersion: protocolVersion
                )
            )
        }

        try await connection.send(
            MumbleVoicePacket.clientAudioPacket(
                opusData: Data(),
                frameNumber: pipeline.takeTerminatorFrameNumber(),
                target: 31,
                isTerminator: true,
                protocolVersion: protocolVersion
            )
        )
    }
}

private actor ProbeStatus {
    private(set) var succeeded = false

    func markSucceeded() {
        succeeded = true
    }
}
