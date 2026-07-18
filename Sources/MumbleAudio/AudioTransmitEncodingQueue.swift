import Foundation

public enum AudioTransmitEncodingResult: Sendable {
    case buffered
    case frame(EncodedAudioFrame)
    case failed(OpusCodecError)
}

/// Keeps Opus work off UI and realtime capture threads while preserving the
/// exact order of 10ms microphone frames and the final terminator.
public final class AudioTransmitEncodingQueue: @unchecked Sendable {
    public typealias EncodeCompletion = @Sendable (AudioTransmitEncodingResult) -> Void
    public typealias FinishCompletion = @Sendable (UInt64?) -> Void

    private let queue = DispatchQueue(
        label: "com.leo.SwiftMumble.audioTransmitEncoding",
        qos: .userInteractive
    )
    private let pendingLock = NSLock()
    private var pendingFrameJobs = 0
    // 80 ms of microphone audio may queue before frames drop — enough to ride
    // out a scheduling burst without adding steady-state latency (the queue
    // drains faster than realtime whenever CPU is available).
    private let maximumPendingFrameJobs = 8
    private var droppedFrameJobs: UInt64 = 0
    private var encodedPackets: UInt64 = 0
    private var pipeline: AudioTransmitPipeline?

    public init() {}

    public func enqueue(
        samples: [Float],
        configuration: OpusEncoderConfiguration,
        framesPerPacket: Int,
        completion: @escaping EncodeCompletion
    ) {
        let accepted = pendingLock.withLock {
            guard pendingFrameJobs < maximumPendingFrameJobs else { return false }
            pendingFrameJobs += 1
            return true
        }
        guard accepted else {
            let dropped = pendingLock.withLock {
                droppedFrameJobs &+= 1
                return droppedFrameJobs
            }
            if dropped == 1 || dropped.isMultiple(of: 50) {
                AudioDiagnostics.shared.record("encode.drop count=\(dropped)")
            }
            return
        }
        queue.async { [self] in
            defer { pendingLock.withLock { pendingFrameJobs -= 1 } }
            do {
                let activePipeline: AudioTransmitPipeline
                if let pipeline {
                    activePipeline = pipeline
                } else {
                    let newPipeline = try AudioTransmitPipeline(
                        configuration: configuration,
                        framesPerPacket: framesPerPacket
                    )
                    pipeline = newPipeline
                    activePipeline = newPipeline
                }
                if let frame = try activePipeline.enqueue10msFrame(samples: samples) {
                    encodedPackets &+= 1
                    if encodedPackets == 1 || encodedPackets.isMultiple(of: 100) {
                        AudioDiagnostics.shared.record(
                            "encode.packet count=\(encodedPackets) pending=\(pendingFrameJobs)"
                        )
                    }
                    deliver(.frame(frame), to: completion)
                } else {
                    deliver(.buffered, to: completion)
                }
            } catch let error as OpusCodecError {
                pipeline = nil
                deliver(.failed(error), to: completion)
            } catch {
                pipeline = nil
                deliver(.failed(.encodingFailed(code: -1)), to: completion)
            }
        }
    }

    public func finish(completion: @escaping FinishCompletion) {
        queue.async { [self] in
            guard let pipeline else {
                deliver(nil, to: completion)
                return
            }
            let frameNumber = pipeline.takeTerminatorFrameNumber()
            self.pipeline = nil
            deliver(frameNumber, to: completion)
        }
    }

    private func deliver(_ result: AudioTransmitEncodingResult, to completion: @escaping EncodeCompletion) {
        completion(result)
    }

    private func deliver(_ frameNumber: UInt64?, to completion: @escaping FinishCompletion) {
        completion(frameNumber)
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return body()
    }
}
