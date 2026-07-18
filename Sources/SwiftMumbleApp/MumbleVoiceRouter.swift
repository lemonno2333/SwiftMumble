import AppKit
import Foundation
import MumbleAudio
import MumbleProtocol
import MumbleSystem

/// Not an actor: the upstream capture path and the downstream UDP receive loop
/// both call into the router at ~10 ms cadence. An actor mailbox would serialize
/// them behind whatever send is currently awaiting the network, letting a busy
/// uplink head-of-line-block the `setUDPAvailable` calls that keep the receive
/// side classified as UDP-active.
final class MumbleVoiceRouter: @unchecked Sendable {
    private let controlConnection: MumbleControlConnection
    private let lock = NSLock()
    private var udpConnection: MumbleUDPConnection?
    private var udpAvailable = false
    private var pendingSends: [Data] = []
    private var isDrainingSends = false
    private let maximumPendingVoicePackets = 48
    private var enqueuedPackets: UInt64 = 0
    private var sentPackets: UInt64 = 0
    private var failedPackets: UInt64 = 0
    private var droppedPackets: UInt64 = 0

    init(controlConnection: MumbleControlConnection) {
        self.controlConnection = controlConnection
    }

    func configureUDP(_ connection: MumbleUDPConnection?) {
        lock.withLock {
            udpConnection = connection
            if connection == nil { udpAvailable = false }
        }
    }

    func setUDPAvailable(_ available: Bool) {
        lock.withLock { udpAvailable = available }
    }

    func enqueue(_ packet: Data) {
        let outcome: (
            startDrain: Bool,
            enqueuedTotal: UInt64,
            pending: Int,
            droppedTotal: UInt64,
            didDrop: Bool
        ) = lock.withLock {
            enqueuedPackets &+= 1
            pendingSends.append(packet)
            var didDrop = false
            if pendingSends.count > maximumPendingVoicePackets {
                let count = pendingSends.count - maximumPendingVoicePackets
                pendingSends.removeFirst(count)
                droppedPackets &+= UInt64(count)
                didDrop = true
            }
            let startDrain = !isDrainingSends
            if startDrain { isDrainingSends = true }
            return (startDrain, enqueuedPackets, pendingSends.count, droppedPackets, didDrop)
        }
        if outcome.didDrop {
            AudioDiagnostics.shared.record(
                "network.drop total=\(outcome.droppedTotal) pending=\(outcome.pending)"
            )
        }
        if outcome.enqueuedTotal == 1 || outcome.enqueuedTotal.isMultiple(of: 100) {
            AudioDiagnostics.shared.record(
                "network.enqueue count=\(outcome.enqueuedTotal) pending=\(outcome.pending)"
            )
        }
        if outcome.startDrain {
            Task.detached(priority: .userInitiated) { [weak self] in
                await self?.drainSends()
            }
        }
    }

    private func drainSends() async {
        while true {
            let next: (packet: Data, udpAvailable: Bool, udp: MumbleUDPConnection?)? = lock.withLock {
                guard !pendingSends.isEmpty else {
                    isDrainingSends = false
                    return nil
                }
                return (pendingSends.removeFirst(), udpAvailable, udpConnection)
            }
            guard let next else { return }
            do {
                try await sendImmediately(next.packet, udpAvailable: next.udpAvailable, udp: next.udp)
                let sent: UInt64 = lock.withLock {
                    sentPackets &+= 1
                    return sentPackets
                }
                if sent == 1 || sent.isMultiple(of: 100) {
                    let pending = lock.withLock { pendingSends.count }
                    AudioDiagnostics.shared.record(
                        "network.sent count=\(sent) pending=\(pending)"
                    )
                }
            } catch {
                let failed: UInt64 = lock.withLock {
                    failedPackets &+= 1
                    return failedPackets
                }
                if failed == 1 || failed.isMultiple(of: 20) {
                    AudioDiagnostics.shared.record(
                        "network.failed count=\(failed) error=\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func sendImmediately(
        _ packet: Data,
        udpAvailable: Bool,
        udp: MumbleUDPConnection?
    ) async throws {
        if udpAvailable, let udp {
            do {
                try await udp.send(packet)
                return
            } catch {
                lock.withLock { self.udpAvailable = false }
            }
        }
        try await controlConnection.send(MumbleFrame(type: .udpTunnel, payload: packet))
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return body()
    }
}
