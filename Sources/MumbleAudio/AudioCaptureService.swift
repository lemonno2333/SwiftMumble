@preconcurrency import AVFAudio
import AVFoundation
import CoreAudio
import Foundation

public enum AudioCaptureError: Error {
    case permissionDenied
    case unsupportedInputFormat
    case converterCreationFailed
    case outputBufferCreationFailed
}

public final class AudioCaptureService: @unchecked Sendable {
    public typealias FrameHandler = @Sendable ([Float]) -> Void

    private let engine = AVAudioEngine()
    private let playbackSource: AVAudioSourceNode
    private let playbackRing: AudioSampleRingBuffer
    private let lock = NSLock()
    private var accumulator = AudioFrameAccumulator()
    private var frameHandler: FrameHandler?
    private var selectedDeviceID: AudioDeviceID?
    private var isCaptureActive = false
    private var isPlaybackActive = false
    private var isTapInstalled = false

    public init() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )!
        let ring = AudioSampleRingBuffer(capacity: 48_000 * 2)
        playbackRing = ring
        playbackSource = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buffer = buffers.first,
                  let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            ring.render(into: data, count: Int(frameCount))
            return noErr
        }
        engine.attach(playbackSource)
        engine.connect(playbackSource, to: engine.mainMixerNode, format: format)
    }

    public func selectDevice(_ deviceID: AudioDeviceID?) {
        selectedDeviceID = deviceID
    }

    public static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    public func start(frameHandler: @escaping FrameHandler) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureError.permissionDenied
        }

        stop()
        self.frameHandler = frameHandler

        let input = engine.inputNode
        if let selectedDeviceID {
            try AudioDeviceManager.select(selectedDeviceID, on: input.audioUnit)
        }
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioCaptureError.unsupportedInputFormat
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.unsupportedInputFormat
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            self?.convert(buffer, using: converter, outputFormat: outputFormat)
        }
        isTapInstalled = true
        isCaptureActive = true

        do {
            try startEngineIfNeeded()
        } catch {
            input.removeTap(onBus: 0)
            isTapInstalled = false
            isCaptureActive = false
            self.frameHandler = nil
            throw error
        }
    }

    public func stop() {
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        isCaptureActive = false
        lock.withLock {
            accumulator.reset()
        }
        frameHandler = nil
        if !isPlaybackActive, engine.isRunning { engine.stop() }
    }

    public func startPlayback() throws {
        isPlaybackActive = true
        do {
            try startEngineIfNeeded()
        } catch {
            isPlaybackActive = false
            throw error
        }
    }

    public func stopPlayback() {
        isPlaybackActive = false
        playbackRing.reset()
        if !isCaptureActive, engine.isRunning { engine.stop() }
    }

    public func selectOutputDevice(_ deviceID: AudioDeviceID?) throws {
        guard let deviceID else { return }
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        try AudioDeviceManager.select(deviceID, on: engine.outputNode.audioUnit)
        if wasRunning { try startEngineIfNeeded() }
    }

    public func enqueuePlayback(samples: [Float]) {
        playbackRing.enqueue(samples)
    }

    public func setPlaybackMuted(_ muted: Bool) {
        playbackRing.setMuted(muted)
    }

    public var bufferedPlaybackSampleCount: Int {
        playbackRing.availableSampleCount
    }

    private func startEngineIfNeeded() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    private func convert(
        _ input: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) {
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        let inputProvider = ConverterInput(buffer: input)
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            inputProvider.next(status: status)
        }

        guard conversionError == nil,
              let channel = output.floatChannelData?.pointee,
              output.frameLength > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        let frames = lock.withLock {
            accumulator.append(samples)
        }
        for frame in frames {
            frameHandler?(frame)
        }
    }
}

private final class ConverterInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var supplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard !supplied else {
            status.pointee = .noDataNow
            return nil
        }
        supplied = true
        status.pointee = .haveData
        return buffer
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return body()
    }
}
