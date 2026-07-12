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
    private var connection: NWConnection?
    private var events: AsyncStream<MumbleUDPEvent>.Continuation?

    public init(cryptState: MumbleCryptState) {
        self.cryptState = cryptState
    }

    public func connect(host: String, port: UInt16) -> AsyncStream<MumbleUDPEvent> {
        disconnect()

        let stream = AsyncStream.makeStream(of: MumbleUDPEvent.self)
        events = stream.continuation
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 64738)
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: .udp
        )
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { await self?.handle(state) }
        }
        connection.start(queue: queue)
        return stream.stream
    }

    public func send(_ plaintext: Data) async throws {
        guard let connection else { throw MumbleControlConnectionError.notConnected }
        let encrypted = try cryptState.encrypt(plaintext)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: encrypted, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    public func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
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
            Task { await self?.handleReceived(data, error: error) }
        }
    }

    private func handleReceived(_ data: Data?, error: NWError?) {
        if let data, let plaintext = try? cryptState.decrypt(data) {
            events?.yield(.packet(plaintext))
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
        events?.finish()
        events = nil
    }
}
