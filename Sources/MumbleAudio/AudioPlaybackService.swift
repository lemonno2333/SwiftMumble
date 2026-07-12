import AVFAudio
import CoreAudio
import Foundation

public enum AudioPlaybackError: Error {
    case formatCreationFailed
}

public final class AudioPlaybackService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let source: AVAudioSourceNode
    private let format: AVAudioFormat
    private let ring: AudioSampleRingBuffer

    public init() throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioPlaybackError.formatCreationFailed
        }
        let ring = AudioSampleRingBuffer(capacity: 48_000 * 2)
        self.format = format
        self.ring = ring
        source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buffer = buffers.first,
                  let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            ring.render(into: data, count: Int(frameCount))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    public func start() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        engine.stop()
        ring.reset()
    }

    public func selectDevice(_ deviceID: AudioDeviceID?) throws {
        guard let deviceID else { return }
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        try AudioDeviceManager.select(deviceID, on: engine.outputNode.audioUnit)
        if wasRunning {
            engine.prepare()
            try engine.start()
        }
    }

    public func enqueue(samples: [Float]) throws {
        ring.enqueue(samples)
    }

    public func setMuted(_ muted: Bool) {
        ring.setMuted(muted)
    }

    public var bufferedSampleCount: Int { ring.availableSampleCount }
}

final class AudioSampleRingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Float]
    private var readIndex = 0
    private var writeIndex = 0
    private var available = 0
    private var lastOutput: Float = 0
    private var wasUnderflowing = true
    private var underflowRampRemaining = 0
    private var fadeInRemaining = 0
    private var isMuted = false
    private let rampSamples = 32

    init(capacity: Int) {
        precondition(capacity > 0)
        storage = [Float](repeating: 0, count: capacity)
    }

    var availableSampleCount: Int { lock.withLock { available } }

    func enqueue(_ samples: [Float]) {
        lock.withLock {
            let source = samples.count > storage.count ? samples.suffix(storage.count) : samples[...]
            for sample in source {
                if available == storage.count {
                    readIndex = (readIndex + 1) % storage.count
                    available -= 1
                }
                storage[writeIndex] = sample
                writeIndex = (writeIndex + 1) % storage.count
                available += 1
            }
        }
    }

    func render(into output: UnsafeMutablePointer<Float>, count: Int) {
        lock.withLock {
            for index in 0..<count {
                if available > 0 {
                    let raw = storage[readIndex]
                    readIndex = (readIndex + 1) % storage.count
                    available -= 1
                    if isMuted {
                        output[index] = 0
                        lastOutput = 0
                        continue
                    }
                    if wasUnderflowing {
                        wasUnderflowing = false
                        fadeInRemaining = rampSamples
                    }
                    let sample: Float
                    if fadeInRemaining > 0 {
                        let progress = Float(rampSamples - fadeInRemaining + 1) / Float(rampSamples)
                        sample = raw * progress
                        fadeInRemaining -= 1
                    } else {
                        sample = raw
                    }
                    output[index] = sample
                    lastOutput = sample
                } else {
                    if !wasUnderflowing {
                        wasUnderflowing = true
                        underflowRampRemaining = rampSamples
                    }
                    if underflowRampRemaining > 0 {
                        let sample = lastOutput * Float(underflowRampRemaining) / Float(rampSamples)
                        output[index] = sample
                        lastOutput = sample
                        underflowRampRemaining -= 1
                    } else {
                        output[index] = 0
                        lastOutput = 0
                    }
                }
            }
        }
    }

    func reset() {
        lock.withLock {
            readIndex = 0
            writeIndex = 0
            available = 0
            lastOutput = 0
            wasUnderflowing = true
            underflowRampRemaining = 0
            fadeInRemaining = 0
        }
    }

    func setMuted(_ muted: Bool) {
        lock.withLock {
            guard isMuted != muted else { return }
            isMuted = muted
            lastOutput = 0
            underflowRampRemaining = 0
            fadeInRemaining = 0
            wasUnderflowing = true
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
