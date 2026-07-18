import Foundation

public enum JitterBufferRead<Packet: Equatable & Sendable>: Equatable, Sendable {
    case waiting
    case packet(frameNumber: UInt64, Packet)
    case missing(frameNumber: UInt64)
}

public struct AudioJitterBuffer<Packet: Equatable & Sendable>: Sendable {
    public private(set) var targetDelayFrames: Int
    public let maximumBufferedFrames: Int

    private var packets: [UInt64: Packet] = [:]
    private var expectedFrameNumber: UInt64?
    private var hasStarted = false

    public init(targetDelayFrames: Int = 3, maximumBufferedFrames: Int = 50) {
        precondition(targetDelayFrames >= 1)
        precondition(maximumBufferedFrames >= targetDelayFrames)
        self.targetDelayFrames = targetDelayFrames
        self.maximumBufferedFrames = maximumBufferedFrames
    }

    public mutating func push(frameNumber: UInt64, packet: Packet) {
        if let expectedFrameNumber, frameNumber < expectedFrameNumber { return }
        packets[frameNumber] = packet

        if packets.count > maximumBufferedFrames,
           let oldest = packets.keys.min() {
            packets.removeValue(forKey: oldest)
        }
    }

    public mutating func updateTargetDelayFrames(_ frames: Int) {
        targetDelayFrames = min(maximumBufferedFrames, max(1, frames))
    }

    /// A packet can contain multiple 10ms Opus frames. `read()` already
    /// advances by one, so the receive pipeline uses this to skip the remaining
    /// frame numbers occupied by that packet.
    public mutating func advanceExpectedFrameNumber(by frames: UInt64) {
        guard frames > 0, let expectedFrameNumber else { return }
        self.expectedFrameNumber = expectedFrameNumber + frames
    }

    public mutating func read() -> JitterBufferRead<Packet> {
        if !hasStarted {
            // Frame numbers advance in 10 ms units, so the buffered *span*
            // (not the packet count) measures how much audio is ready. This
            // keeps the configured delay meaning "frames × 10 ms" regardless
            // of how many frames the sender packs per packet.
            // `last - first` is unsigned and can exceed Int.max when a hostile
            // peer sends wildly separated frame numbers, so compare the span in
            // UInt64 space rather than narrowing to Int (which would trap on the
            // mix-clock thread). targetDelayFrames is >= 1 by construction.
            guard let first = packets.keys.min(), let last = packets.keys.max(),
                  last - first >= UInt64(targetDelayFrames) - 1 else {
                return .waiting
            }
            expectedFrameNumber = first
            hasStarted = true
        }

        guard let expectedFrameNumber else { return .waiting }
        self.expectedFrameNumber = expectedFrameNumber + 1

        if let packet = packets.removeValue(forKey: expectedFrameNumber) {
            return .packet(frameNumber: expectedFrameNumber, packet)
        }
        if packets.keys.contains(where: { $0 > expectedFrameNumber }) {
            return .missing(frameNumber: expectedFrameNumber)
        }

        self.expectedFrameNumber = expectedFrameNumber
        return .waiting
    }

    public mutating func reset() {
        packets.removeAll(keepingCapacity: true)
        expectedFrameNumber = nil
        hasStarted = false
    }
}
