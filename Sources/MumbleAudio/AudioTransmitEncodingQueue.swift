import Foundation

public enum AudioTransmitEncodingResult: Sendable {
    case buffered
    case frame(EncodedAudioFrame)
    case failed(OpusCodecError)
}

/// Keeps Opus work off UI and realtime capture threads while preserving the
/// exact order of 10ms microphone frames and the final terminator.
public final class AudioTransmitEncodingQueue: @unchecked Sendable {
    public typealias EncodeCompletion = @MainActor @Sendable (AudioTransmitEncodingResult) -> Void
    public typealias FinishCompletion = @MainActor @Sendable (UInt64?) -> Void

    private let queue = DispatchQueue(
        label: "com.leo.SwiftMumble.audioTransmitEncoding",
        qos: .userInteractive
    )
    private var pipeline: AudioTransmitPipeline?

    public init() {}

    public func enqueue(
        samples: [Float],
        configuration: OpusEncoderConfiguration,
        framesPerPacket: Int,
        completion: @escaping EncodeCompletion
    ) {
        queue.async { [self] in
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
        DispatchQueue.main.async {
            MainActor.assumeIsolated { completion(result) }
        }
    }

    private func deliver(_ frameNumber: UInt64?, to completion: @escaping FinishCompletion) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { completion(frameNumber) }
        }
    }
}
