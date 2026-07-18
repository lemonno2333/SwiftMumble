import Foundation
import MumbleAudio
import MumbleProtocol

struct AudioIngressEvent: Sendable {
    var session: UInt32
    var isTerminator: Bool
    var isSelfAudio: Bool
    var isNewSource: Bool
}

/// Owns the realtime receive path so network audio never waits for MainActor.
///
/// Packets arriving off the UDP/TCP loop are pushed into per-speaker jitter
/// buffers. A single mix clock (`AudioMixClock`) pulls one 10 ms frame from
/// every speaker on a steady cadence, mixes them, and enqueues the result into
/// the playback ring — so the CoreAudio render thread only ever memcpys.
final class AudioReceiveIngress: @unchecked Sendable {
    private let lock = NSLock()
    private let mixer: AudioFrameMixer
    private var pipelines: [UInt32: AudioReceivePipeline] = [:]
    /// Immutable snapshot rebuilt on membership changes so the 100 Hz mix
    /// clock can grab it without copying.
    private var pipelineList: [(UInt32, AudioReceivePipeline)] = []
    private var ownSession: UInt32?
    private var targetDelayFrames = 3
    private var mixClock: AudioMixClock?

    init(mixer: AudioFrameMixer) {
        self.mixer = mixer
    }

    func configure(ownSession: UInt32?, targetDelayFrames: Int) {
        lock.withLock {
            self.ownSession = ownSession
            self.targetDelayFrames = targetDelayFrames
        }
    }

    /// Starts the mix clock, wiring pulled frames into `playback`. Idempotent.
    func startMixClock(playback: AudioPlaybackBackend, referenceSink: AudioInputProcessor?) {
        lock.withLock {
            guard mixClock == nil else { return }
            let clock = AudioMixClock(
                mixer: mixer,
                playback: playback,
                referenceSink: referenceSink,
                snapshot: { [weak self] in self?.activePipelines() ?? [] }
            )
            mixClock = clock
            clock.start()
        }
    }

    func stopMixClock() {
        let clock = lock.withLock { () -> AudioMixClock? in
            let clock = mixClock
            mixClock = nil
            return clock
        }
        clock?.stop()
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

    /// Total concealed frames across all live speakers — health metric for the
    /// multi-speaker stress path.
    var concealedFrameCount: UInt64 {
        lock.withLock { pipelines.values.reduce(0) { $0 + $1.concealedFrameCount } }
    }

    private func activePipelines() -> [(UInt32, AudioReceivePipeline)] {
        lock.withLock { pipelineList }
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
                isSelfAudio: true,
                isNewSource: false
            )
        }

        let resolved = try pipeline(for: incoming.senderSession, targetDelayFrames: configuration.1)
        resolved.pipeline.push(
            frameNumber: incoming.frameNumber,
            packet: BufferedAudioPacket(
                opusData: incoming.opusData,
                volume: incoming.volumeAdjustment,
                isTerminator: incoming.isTerminator
            )
        )
        return AudioIngressEvent(
            session: incoming.senderSession,
            isTerminator: incoming.isTerminator,
            isSelfAudio: false,
            isNewSource: resolved.isNew
        )
    }

    func remove(session: UInt32) {
        lock.withLock {
            pipelines.removeValue(forKey: session)
            pipelineList = pipelines.map { ($0.key, $0.value) }
        }
        mixer.unregister(source: session)
    }

    func removeAll() {
        lock.withLock {
            pipelines.removeAll()
            pipelineList = []
            ownSession = nil
        }
        mixer.removeAllSources()
    }

    private func pipeline(
        for session: UInt32,
        targetDelayFrames: Int
    ) throws -> (pipeline: AudioReceivePipeline, isNew: Bool) {
        if let existing = lock.withLock({ pipelines[session] }) { return (existing, false) }

        let pipeline = try AudioReceivePipeline(targetDelayFrames: targetDelayFrames)
        let installed = lock.withLock { () -> (AudioReceivePipeline, Bool) in
            if let existing = pipelines[session] { return (existing, false) }
            pipelines[session] = pipeline
            pipelineList = pipelines.map { ($0.key, $0.value) }
            mixer.register(source: session)
            return (pipeline, true)
        }
        return installed
    }
}

/// Drives the 10 ms mix on a dedicated high-priority timer, off both the
/// CoreAudio render thread and the MainActor.
private final class AudioMixClock: @unchecked Sendable {
    private let mixer: AudioFrameMixer
    private let playback: AudioPlaybackBackend
    private let referenceSink: AudioInputProcessor?
    private let snapshot: @Sendable () -> [(UInt32, AudioReceivePipeline)]
    private let queue = DispatchQueue(label: "com.leo.SwiftMumble.audioMix", qos: .userInteractive)
    private let timer: DispatchSourceTimer
    private let frameLength = 480
    private let targetBufferedFrames = 3

    // Reused across ticks; only the mix-clock queue touches these.
    private let sourceScratch: UnsafeMutablePointer<Float>
    private let mixScratch: UnsafeMutablePointer<Float>

    init(
        mixer: AudioFrameMixer,
        playback: AudioPlaybackBackend,
        referenceSink: AudioInputProcessor?,
        snapshot: @escaping @Sendable () -> [(UInt32, AudioReceivePipeline)]
    ) {
        self.mixer = mixer
        self.playback = playback
        self.referenceSink = referenceSink
        self.snapshot = snapshot
        sourceScratch = .allocate(capacity: frameLength)
        sourceScratch.initialize(repeating: 0, count: frameLength)
        mixScratch = .allocate(capacity: frameLength)
        mixScratch.initialize(repeating: 0, count: frameLength)
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
    }

    deinit {
        sourceScratch.deinitialize(count: frameLength)
        sourceScratch.deallocate()
        mixScratch.deinitialize(count: frameLength)
        mixScratch.deallocate()
    }

    func start() {
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
    }

    func stop() {
        timer.setEventHandler {}
        timer.cancel()
    }

    private func tick() {
        // Top the ring up to ~30 ms ahead of the render thread, producing only
        // when below target: a scheduling hiccup is refilled in one tick, and
        // clock drift against the output device self-corrects by skipping.
        let targetSamples = targetBufferedFrames * frameLength
        let buffered = playback.bufferedSampleCount
        guard buffered < targetSamples else { return }
        let deficitFrames = (targetSamples - buffered + frameLength - 1) / frameLength
        let framesToProduce = min(deficitFrames, targetBufferedFrames + 1)

        let sources = snapshot()
        for _ in 0..<framesToProduce {
            mixer.beginFrame()
            var active = 0
            for (session, pipeline) in sources where pipeline.pull(into: sourceScratch) {
                mixer.accumulate(source: session, samples: sourceScratch)
                active += 1
            }
            // Only feed the ring while someone is talking; otherwise let it
            // drain naturally so resumed speech starts with zero queued latency.
            guard active > 0 else { return }
            mixer.finalizeFrame(into: mixScratch)
            referenceSink?.tryUpdatePlaybackReference(pointer: mixScratch, count: frameLength)
            playback.enqueue(samples: mixScratch, count: frameLength)
        }
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
