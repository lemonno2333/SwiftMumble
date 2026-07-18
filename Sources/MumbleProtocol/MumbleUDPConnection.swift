import Foundation
import Network

public enum MumbleUDPEvent: Sendable {
    case ready
    case packet(Data)
    case failed(message: String)
    case disconnected
}

public actor MumbleUDPConnection {
    private let queue = DispatchQueue(label: "com.leo.SwiftMumble.udp")
    private let cryptState: MumbleCryptState
    private nonisolated let sendPath: MumbleUDPSendPath
    private nonisolated let diagnostics: MumbleUDPDiagnosticsProbe
    private var connection: NWConnection?
    private var events: AsyncStream<MumbleUDPEvent>.Continuation?

    public init(
        cryptState: MumbleCryptState,
        diagnosticsHandler: (@Sendable (String) -> Void)? = nil
    ) {
        self.cryptState = cryptState
        sendPath = MumbleUDPSendPath(cryptState: cryptState)
        diagnostics = MumbleUDPDiagnosticsProbe(handler: diagnosticsHandler)
    }

    public func connect(host: String, port: UInt16) -> AsyncStream<MumbleUDPEvent> {
        disconnect()

        let stream = AsyncStream.makeStream(of: MumbleUDPEvent.self)
        events = stream.continuation
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 64738)
        let parameters: NWParameters = .udp
        parameters.serviceClass = .interactiveVoice
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: parameters
        )
        self.connection = connection
        sendPath.setConnection(connection)
        connection.stateUpdateHandler = { [weak self] state in
            Task { await self?.handle(state) }
        }
        connection.start(queue: queue)
        return stream.stream
    }

    public nonisolated func send(_ plaintext: Data) async throws {
        try await sendPath.send(plaintext)
    }

    /// Packets that arrived but failed authentication/decryption. A rising
    /// count with no successful decrypts is the signature of OCB2 nonce
    /// desynchronization and gates the crypt-resync request.
    public nonisolated var rejectedPacketCount: UInt64 {
        diagnostics.rejectedPacketCount
    }

    public func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        sendPath.setConnection(nil)
        events?.yield(.disconnected)
        events?.finish()
        events = nil
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            events?.yield(.ready)
            receiveNextPacket()
        case .failed(let error):
            events?.yield(.failed(message: error.localizedDescription))
            finish()
        case .cancelled:
            events?.yield(.disconnected)
            finish()
        default:
            break
        }
    }

    private func receiveNextPacket() {
        guard let connection else { return }
        connection.receiveMessage { [weak self] data, _, _, error in
            self?.diagnostics.recordRaw(data: data, error: error)
            Task { await self?.handleReceived(data, error: error) }
        }
    }

    private func handleReceived(_ data: Data?, error: NWError?) {
        if let data {
            do {
                if let plaintext = try cryptState.decrypt(data) {
                    diagnostics.recordDecrypted(byteCount: plaintext.count)
                    events?.yield(.packet(plaintext))
                } else {
                    diagnostics.recordRejected(reason: "authentication-or-replay")
                }
            } catch {
                diagnostics.recordRejected(reason: String(describing: error))
            }
        }
        if let error {
            events?.yield(.failed(message: error.localizedDescription))
            finish()
        } else {
            receiveNextPacket()
        }
    }

    private func finish() {
        connection = nil
        sendPath.setConnection(nil)
        events?.finish()
        events = nil
    }
}

private final class MumbleUDPDiagnosticsProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let handler: (@Sendable (String) -> Void)?
    private var rawCount: UInt64 = 0
    private var decryptedCount: UInt64 = 0
    private var rejectedCount: UInt64 = 0

    init(handler: (@Sendable (String) -> Void)?) {
        self.handler = handler
    }

    var rejectedPacketCount: UInt64 {
        lock.withLock { rejectedCount }
    }

    func recordRaw(data: Data?, error: NWError?) {
        let message = lock.withLock { () -> String? in
            rawCount &+= 1
            guard rawCount == 1 || rawCount.isMultiple(of: 100) || error != nil else { return nil }
            let errorDescription = error?.localizedDescription ?? "none"
            return "udp.raw count=\(rawCount) bytes=\(data?.count ?? 0) error=\(errorDescription)"
        }
        if let message { handler?(message) }
    }

    func recordDecrypted(byteCount: Int) {
        let message = lock.withLock { () -> String? in
            decryptedCount &+= 1
            guard decryptedCount == 1 || decryptedCount.isMultiple(of: 100) else { return nil }
            return "udp.decrypted count=\(decryptedCount) bytes=\(byteCount)"
        }
        if let message { handler?(message) }
    }

    func recordRejected(reason: String) {
        let message = lock.withLock { () -> String? in
            rejectedCount &+= 1
            guard rejectedCount == 1 || rejectedCount.isMultiple(of: 20) else { return nil }
            return "udp.rejected count=\(rejectedCount) reason=\(reason)"
        }
        if let message { handler?(message) }
    }
}

/// Keeps high-frequency voice sends out of the UDP actor's mailbox so receive
/// callbacks cannot be delayed behind a continuous stream of outgoing audio.
private final class MumbleUDPSendPath: @unchecked Sendable {
    private let lock = NSLock()
    private let cryptState: MumbleCryptState
    private var connection: NWConnection?

    init(cryptState: MumbleCryptState) {
        self.cryptState = cryptState
    }

    func setConnection(_ connection: NWConnection?) {
        lock.withLock { self.connection = connection }
    }

    func send(_ plaintext: Data) async throws {
        guard let connection = lock.withLock({ connection }) else {
            throw MumbleControlConnectionError.notConnected
        }
        let encrypted = try cryptState.encrypt(plaintext)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: encrypted, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return body()
    }
}
