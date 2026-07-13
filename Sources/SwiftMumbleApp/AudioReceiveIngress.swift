import Foundation
import MumbleAudio
import MumbleProtocol

struct AudioIngressEvent: Sendable {
    var session: UInt32
    var isTerminator: Bool
    var isSelfAudio: Bool
}

/// Owns the realtime receive path so network audio never waits for MainActor.
final class AudioReceiveIngress: @unchecked Sendable {
    private let lock = NSLock()
    private let mixer: AudioFrameMixer
    private var pipelines: [UInt32: AudioReceivePipeline] = [:]
    private var drainWorkers: [UInt32: AudioDrainWorker] = [:]
    private var ownSession: UInt32?
    private var targetDelayFrames = 3

    init(mixer: AudioFrameMixer) {
        self.mixer = mixer
    }

    func configure(ownSession: UInt32?, targetDelayFrames: Int) {
        lock.withLock {
            self.ownSession = ownSession
            self.targetDelayFrames = targetDelayFrames
        }
    }

    var pipelineCount: Int {
        lock.withLock { pipelines.count }
    }

    var averageJitterMilliseconds: Double {
        let values = lock.withLock { pipelines.values.map(\.estimatedJitterMilliseconds) }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageBufferMilliseconds: Int? {
        let values = lock.withLock { pipelines.values.map(\.targetDelayFrames) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) * 10 / values.count
    }

    func receive(payload: Data) throws -> AudioIngressEvent {
        let incoming = try MumbleVoicePacket.decodeTunneledAudio(
            MumbleFrame(type: .udpTunnel, payload: payload)
        )
        let configuration = lock.withLock { (ownSession, targetDelayFrames) }
        if incoming.senderSession == configuration.0 {
            return AudioIngressEvent(
                session: incoming.senderSession,
                isTerminator: incoming.isTerminator,
                isSelfAudio: true
            )
        }

        let pipeline = try pipeline(for: incoming.senderSession, targetDelayFrames: configuration.1)
        pipeline.push(
            frameNumber: incoming.frameNumber,
            packet: BufferedAudioPacket(
                opusData: incoming.opusData,
                volume: incoming.volumeAdjustment,
                isTerminator: incoming.isTerminator
            )
        )
        lock.withLock { drainWorkers[incoming.senderSession] }?.notifyPacketArrival()
        return AudioIngressEvent(
            session: incoming.senderSession,
            isTerminator: incoming.isTerminator,
            isSelfAudio: false
        )
    }

    func remove(session: UInt32) {
        let worker = lock.withLock { () -> AudioDrainWorker? in
            pipelines.removeValue(forKey: session)
            return drainWorkers.removeValue(forKey: session)
        }
        worker?.cancel()
        mixer.unregister(source: session)
    }

    func removeAll() {
        let workers = lock.withLock { () -> [AudioDrainWorker] in
            let workers = Array(drainWorkers.values)
            drainWorkers.removeAll()
            pipelines.removeAll()
            ownSession = nil
            return workers
        }
        workers.forEach { $0.cancel() }
        mixer.removeAllSources()
    }

    private func pipeline(for session: UInt32, targetDelayFrames: Int) throws -> AudioReceivePipeline {
        if let existing = lock.withLock({ pipelines[session] }) { return existing }

        let pipeline = try AudioReceivePipeline(targetDelayFrames: targetDelayFrames)
        let worker = AudioDrainWorker(session: session, pipeline: pipeline, mixer: mixer)
        let installed = lock.withLock { () -> AudioReceivePipeline in
            if let existing = pipelines[session] {
                worker.cancel()
                return existing
            }
            pipelines[session] = pipeline
            drainWorkers[session] = worker
            mixer.register(source: session)
            worker.start()
            return pipeline
        }
        return installed
    }
}

private final class AudioDrainWorker: @unchecked Sendable {
    private let session: UInt32
    private let pipeline: AudioReceivePipeline
    private let mixer: AudioFrameMixer
    private let queue: DispatchQueue
    private let packetSignal = DispatchSemaphore(value: 0)
    private let stateLock = NSLock()
    private var cancelled = false

    init(session: UInt32, pipeline: AudioReceivePipeline, mixer: AudioFrameMixer) {
        self.session = session
        self.pipeline = pipeline
        self.mixer = mixer
        queue = DispatchQueue(
            label: "com.leo.SwiftMumble.audioDrain.\(session)",
            qos: .userInteractive
        )
    }

    func start() {
        queue.async { [self] in drain() }
    }

    func cancel() {
        stateLock.withLock { cancelled = true }
        packetSignal.signal()
    }

    func notifyPacketArrival() {
        packetSignal.signal()
    }

    private func drain() {
        var sampleReads: UInt64 = 0
        AudioDiagnostics.shared.record("drain.start session=\(session)")
        while !stateLock.withLock({ cancelled }) {
            packetSignal.wait()
            while !stateLock.withLock({ cancelled }) {
                do {
                    switch try pipeline.read() {
                    case .waiting:
                        break
                    case .samples(let samples):
                        sampleReads &+= 1
                        if sampleReads == 1 || sampleReads.isMultiple(of: 100) {
                            AudioDiagnostics.shared.record("drain.samples session=\(session) count=\(sampleReads)")
                        }
                        mixer.push(source: session, samples: samples)
                        continue
                    case .finished:
                        AudioDiagnostics.shared.record("drain.terminator session=\(session) samples=\(sampleReads)")
                        continue
                    }
                } catch {
                    AudioDiagnostics.shared.record("drain.error session=\(session) error=\(error.localizedDescription)")
                }
                break
            }
        }
        AudioDiagnostics.shared.record("drain.cancelled session=\(session) samples=\(sampleReads)")
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
