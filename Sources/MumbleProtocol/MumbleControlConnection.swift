import Foundation
import Network
import Security

public enum MumbleConnectionEvent: Sendable {
    case preparing
    case ready
    case frame(MumbleFrame)
    case waiting(message: String)
    case untrustedCertificate(subject: String, fingerprint: MumbleCertificateFingerprint)
    case certificateMismatch(
        subject: String,
        expected: MumbleCertificateFingerprint,
        actual: MumbleCertificateFingerprint
    )
    case failed(message: String)
    case disconnected
}

public struct MumbleTLSClientIdentity: @unchecked Sendable {
    fileprivate let identity: SecIdentity

    public init(_ identity: SecIdentity) {
        self.identity = identity
    }
}

public enum MumbleProxyType: String, Codable, Sendable { case none, socks5, httpConnect }
public struct MumbleProxyConfiguration: Codable, Equatable, Sendable {
    public var type: MumbleProxyType; public var host: String; public var port: UInt16
    public var username: String; public var password: String
    public init(type: MumbleProxyType = .none, host: String = "", port: UInt16 = 1080,
                username: String = "", password: String = "") {
        self.type = type; self.host = host; self.port = port; self.username = username; self.password = password
    }
}

/// TLS control connection for the framed Mumble TCP protocol.
///
/// Certificate pinning and user-approved self-signed certificates will be
/// added with the Keychain identity layer. The initial implementation uses
/// the system trust store.
public actor MumbleControlConnection {
    private let queue = DispatchQueue(label: "com.leo.SwiftMumble.control")
    private var connection: NWConnection?
    private var decoder = MumbleFrameDecoder()
    private var events: AsyncStream<MumbleConnectionEvent>.Continuation?

    public init() {}

    public func connect(
        host: String,
        port: UInt16,
        pinnedCertificateSHA256: Data? = nil,
        clientIdentity: MumbleTLSClientIdentity? = nil,
        connectionTimeoutSeconds: UInt32 = 15,
        proxy: MumbleProxyConfiguration = .init()
    ) -> AsyncStream<MumbleConnectionEvent> {
        disconnect()

        let stream = AsyncStream.makeStream(of: MumbleConnectionEvent.self)
        events = stream.continuation
        let eventContinuation = stream.continuation

        let tlsOptions = NWProtocolTLS.Options()
        if let clientIdentity,
           let protocolIdentity = sec_identity_create(clientIdentity.identity) {
            sec_protocol_options_set_local_identity(
                tlsOptions.securityProtocolOptions,
                protocolIdentity
            )
        }
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, trust, completion in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
                      let certificate = chain.first else {
                    completion(false)
                    return
                }
                let certificateData = SecCertificateCopyData(certificate) as Data
                let fingerprint = MumbleCertificateFingerprint(certificateDER: certificateData)
                let subject = SecCertificateCopySubjectSummary(certificate) as String? ?? "Unknown certificate"

                switch MumbleCertificatePinEvaluator.evaluate(
                    actual: fingerprint,
                    pinnedSHA256: pinnedCertificateSHA256
                ) {
                case .match:
                    completion(true)
                    return
                case .mismatch(let expected, let actual):
                    eventContinuation.yield(
                        .certificateMismatch(subject: subject, expected: expected, actual: actual)
                    )
                    completion(false)
                    return
                case .invalidPinnedFingerprint:
                    completion(false)
                    return
                case .notPinned:
                    break
                }

                var trustError: CFError?
                if SecTrustEvaluateWithError(secTrust, &trustError) {
                    completion(true)
                } else {
                    eventContinuation.yield(
                        .untrustedCertificate(subject: subject, fingerprint: fingerprint)
                    )
                    completion(false)
                }
            },
            queue
        )
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.connectionTimeout = Int(min(120, max(5, connectionTimeoutSeconds)))
        // Home NAT/Wi-Fi idle timeouts drop the control socket before app-level ping notices.
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 15
        tcpOptions.keepaliveInterval = 5
        tcpOptions.keepaliveCount = 3
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        parameters.serviceClass = .interactiveVoice
        if proxy.type != .none, !proxy.host.isEmpty,
           let proxyPort = NWEndpoint.Port(rawValue: proxy.port) {
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(proxy.host), port: proxyPort)
            let configuration = proxy.type == .socks5
                ? ProxyConfiguration(socksv5Proxy: endpoint)
                : ProxyConfiguration(httpCONNECTProxy: endpoint)
            if !proxy.username.isEmpty { configuration.applyCredential(username: proxy.username, password: proxy.password) }
            let privacy = NWParameters.PrivacyContext(description: "Mumble Proxy")
            privacy.proxyConfigurations = [configuration]
            parameters.setPrivacyContext(privacy)
        }

        let endpointPort = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 64738)
        let newConnection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: parameters
        )
        connection = newConnection

        newConnection.stateUpdateHandler = { [weak self] state in
            Task { await self?.handle(state) }
        }
        newConnection.start(queue: queue)
        events?.yield(.preparing)

        return stream.stream
    }

    public func send(_ frame: MumbleFrame) async throws {
        guard let connection else {
            throw MumbleControlConnectionError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame.encoded(), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        decoder = MumbleFrameDecoder()
        events?.yield(.disconnected)
        events?.finish()
        events = nil
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .setup, .preparing:
            events?.yield(.preparing)
        case .ready:
            events?.yield(.ready)
            receiveNextChunk()
        case .waiting(let error):
            events?.yield(.waiting(message: error.localizedDescription))
        case .failed(let error):
            events?.yield(.failed(message: error.localizedDescription))
            finishConnection()
        case .cancelled:
            events?.yield(.disconnected)
            finishConnection()
        @unknown default:
            events?.yield(.failed(message: "Unknown Network.framework state"))
            finishConnection()
        }
    }

    private func receiveNextChunk() {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task {
                await self?.handleReceivedData(data, isComplete: isComplete, error: error)
            }
        }
    }

    private func handleReceivedData(_ data: Data?, isComplete: Bool, error: NWError?) {
        if let data, !data.isEmpty {
            do {
                for frame in try decoder.append(data) {
                    events?.yield(.frame(frame))
                }
            } catch {
                events?.yield(.failed(message: "Invalid Mumble frame: \(error)"))
                connection?.cancel()
                return
            }
        }

        if let error {
            events?.yield(.failed(message: error.localizedDescription))
            connection?.cancel()
        } else if isComplete {
            events?.yield(.disconnected)
            connection?.cancel()
        } else {
            receiveNextChunk()
        }
    }

    private func finishConnection() {
        connection = nil
        events?.finish()
        events = nil
    }
}

public enum MumbleControlConnectionError: Error {
    case notConnected
}
