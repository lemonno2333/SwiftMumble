import Foundation
import MumbleProtocol
import Network

struct ServerPingResult: Sendable {
    var latencyMilliseconds: Double
    var users: UInt32
    var maximumUsers: UInt32
    var bandwidth: UInt32
}

enum ServerPingService {
    static func ping(host: String, port: UInt16, timeout: TimeInterval = 2) async throws -> ServerPingResult {
        let started = ProcessInfo.processInfo.systemUptime
        let timestamp = UInt64(started * 1_000_000)
        let packet = MumbleUDPPacket.legacyServerListPing(timestamp: timestamp)
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? 64738
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .udp)
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.leo.SwiftMumble.serverPing")
            let completion = ServerPingCompletion(connection: connection, continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if let error { completion.finish(.failure(error)); return }
                        connection.receiveMessage { data, _, _, error in
                            do {
                                if let error { throw error }
                                guard let data, let response = try MumbleUDPPacket.serverListPingResponse(from: data),
                                      response.timestamp == timestamp else { throw URLError(.cannotParseResponse) }
                                completion.finish(.success(ServerPingResult(
                                    latencyMilliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1_000,
                                    users: response.userCount, maximumUsers: response.maxUserCount,
                                    bandwidth: response.maxBandwidthPerUser
                                )))
                            } catch { completion.finish(.failure(error)) }
                        }
                    })
                case .failed(let error): completion.finish(.failure(error))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { completion.finish(.failure(URLError(.timedOut))) }
        }
    }
}

private final class ServerPingCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let connection: NWConnection
    private let continuation: CheckedContinuation<ServerPingResult, Error>
    init(connection: NWConnection, continuation: CheckedContinuation<ServerPingResult, Error>) {
        self.connection = connection; self.continuation = continuation
    }
    func finish(_ result: Result<ServerPingResult, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return }; completed = true
        connection.cancel(); continuation.resume(with: result)
    }
}
