import AudioToolbox
import CoreAudio
import Darwin
import Foundation

public enum AudioPlaybackError: Error {
    case audioComponentUnavailable
    case coreAudio(OSStatus)
}

public final class AudioPlaybackService: @unchecked Sendable {
    public typealias FillHandler = @Sendable () -> Bool

    private let ring: AudioSampleRingBuffer
    private let overlayRing: AudioSampleRingBuffer
    private let configurationLock = NSLock()
    private let fillLock = NSLock()
    private let scratchCapacity = 8_192
    private let scratch: UnsafeMutablePointer<Float>
    private var selectedDeviceID: AudioDeviceID?
    private var audioUnit: AudioUnit?
    private var isRunning = false
    private var renderCount: UInt64 = 0
    private var fillHandler: FillHandler?

    public init() throws {
        let ring = AudioSampleRingBuffer(capacity: 48_000 * 2)
        let overlayRing = AudioSampleRingBuffer(capacity: 48_000)
        self.ring = ring
        self.overlayRing = overlayRing
        scratch = .allocate(capacity: scratchCapacity)
        scratch.initialize(repeating: 0, count: scratchCapacity)
    }

    deinit {
        shutdown()
        scratch.deinitialize(count: scratchCapacity)
        scratch.deallocate()
    }

    public func start() throws {
        try configurationLock.withLock {
            guard !isRunning else { return }
            try prepareUnlocked()
            guard let audioUnit else { throw AudioPlaybackError.audioComponentUnavailable }
            try Self.check(AudioOutputUnitStart(audioUnit))
            isRunning = true
            AudioDiagnostics.shared.record("playback.start")
        }
    }

    public func stop() {
        configurationLock.withLock { stopUnlocked() }
    }

    public func selectDevice(_ deviceID: AudioDeviceID?) throws {
        try configurationLock.withLock {
            guard selectedDeviceID != deviceID else { return }
            let restart = isRunning
            shutdownUnlocked()
            selectedDeviceID = deviceID
            if restart {
                try prepareUnlocked()
                guard let audioUnit else { throw AudioPlaybackError.audioComponentUnavailable }
                try Self.check(AudioOutputUnitStart(audioUnit))
                isRunning = true
            }
        }
    }

    public func enqueue(samples: [Float]) throws {
        ring.enqueue(samples)
    }

    public func enqueueOverlay(samples: [Float]) {
        overlayRing.enqueue(samples)
    }

    public func setMuted(_ muted: Bool) {
        ring.setMuted(muted)
        overlayRing.setMuted(muted)
    }

    public var bufferedSampleCount: Int { ring.availableSampleCount }

    public func setFillHandler(_ handler: FillHandler?) {
        fillLock.withLock { fillHandler = handler }
    }

    /// Matches the workaround used by official Mumble and Mozilla cubeb for
    /// macOS voice-capture sessions that automatically duck the output device.
    public func undoSystemVoiceDucking() {
        let deviceID = configurationLock.withLock { audioUnit.flatMap(Self.currentDeviceID) }
        guard let deviceID,
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AudioDeviceDuck") else {
            AudioDiagnostics.shared.record("playback.unduck unavailable")
            return
        }
        typealias AudioDeviceDuckFunction = @convention(c) (
            AudioDeviceID,
            Float32,
            UnsafePointer<AudioTimeStamp>?,
            Float32
        ) -> OSStatus
        let audioDeviceDuck = unsafeBitCast(symbol, to: AudioDeviceDuckFunction.self)
        let status = audioDeviceDuck(deviceID, 1, nil, 0.5)
        AudioDiagnostics.shared.record("playback.unduck device=\(deviceID) status=\(status)")
    }

    fileprivate func render(frameCount: UInt32, outputData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        guard isRunning, frameCount <= scratchCapacity else {
            Self.clear(outputData, frameCount: frameCount)
            return noErr
        }
        let count = Int(frameCount)
        renderCount &+= 1
        runFillHandler()
        ring.render(into: scratch, count: count)
        overlayRing.mix(into: scratch, count: count)
        if renderCount == 1 || renderCount.isMultiple(of: 100) {
            let renders = renderCount
            let buffered = ring.availableSampleCount
            var peak: Float = 0
            for index in 0..<count { peak = max(peak, abs(scratch[index])) }
            AudioDiagnostics.shared.record(
                "playback.render count=\(renders) frames=\(frameCount) buffered=\(buffered) peak=\(peak)"
            )
        }

        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let channels = max(1, Int(buffer.mNumberChannels))
            if channels == 1 {
                data.update(from: scratch, count: count)
            } else {
                for frame in 0..<count {
                    for channel in 0..<channels { data[frame * channels + channel] = scratch[frame] }
                }
            }
        }
        return noErr
    }

    private func runFillHandler() {
        guard fillLock.try() else { return }
        let handler = fillHandler
        fillLock.unlock()
        guard let handler else { return }
        if !handler() { fillLock.withLock { fillHandler = nil } }
    }

    private func prepareUnlocked() throws {
        guard audioUnit == nil else { return }
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioPlaybackError.audioComponentUnavailable
        }
        var unit: AudioUnit?
        try Self.check(AudioComponentInstanceNew(component, &unit))
        guard let unit else { throw AudioPlaybackError.audioComponentUnavailable }

        do {
            var enabled: UInt32 = 1
            try Self.check(AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                &enabled, UInt32(MemoryLayout<UInt32>.size)
            ))
            var disabled: UInt32 = 0
            try Self.check(AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                &disabled, UInt32(MemoryLayout<UInt32>.size)
            ))
            var deviceID = try selectedDeviceID ?? Self.defaultOutputDeviceID()
            try Self.check(AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
            ))

            var hardwareFormat = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioUnitGetProperty(
                unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0,
                &hardwareFormat, &formatSize
            ))
            let channels = max(1, hardwareFormat.mChannelsPerFrame)
            var clientFormat = AudioStreamBasicDescription(
                mSampleRate: 48_000,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
                mFramesPerPacket: 1,
                mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
                mChannelsPerFrame: channels,
                mBitsPerChannel: 32,
                mReserved: 0
            )
            try Self.check(AudioUnitSetProperty(
                unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                &clientFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            ))
            var callback = AURenderCallbackStruct(
                inputProc: audioPlaybackRenderCallback,
                inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
            )
            try Self.check(AudioUnitSetProperty(
                unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0,
                &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            ))
            try Self.check(AudioUnitInitialize(unit))
            audioUnit = unit
        } catch {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            throw error
        }
    }

    private func stopUnlocked() {
        if isRunning, let audioUnit { AudioOutputUnitStop(audioUnit) }
        isRunning = false
        AudioDiagnostics.shared.record("playback.stop renders=\(renderCount)")
        ring.reset()
        overlayRing.reset()
        setFillHandler(nil)
    }

    private func shutdown() {
        configurationLock.withLock { shutdownUnlocked() }
    }

    private func shutdownUnlocked() {
        stopUnlocked()
        guard let audioUnit else { return }
        self.audioUnit = nil
        AudioUnitUninitialize(audioUnit)
        AudioComponentInstanceDispose(audioUnit)
    }

    private static func defaultOutputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ))
        return deviceID
    }

    private static func currentDeviceID(_ audioUnit: AudioUnit) -> AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            &size
        )
        return status == noErr ? deviceID : nil
    }

    private static func clear(_ outputData: UnsafeMutablePointer<AudioBufferList>, frameCount: UInt32) {
        for buffer in UnsafeMutableAudioBufferListPointer(outputData) {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw AudioPlaybackError.coreAudio(status) }
    }
}

private let audioPlaybackRenderCallback: AURenderCallback = {
    reference, _, _, _, frameCount, outputData in
    let service = Unmanaged<AudioPlaybackService>.fromOpaque(reference).takeUnretainedValue()
    guard let outputData else { return noErr }
    return service.render(frameCount: frameCount, outputData: outputData)
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
        render(into: output, count: count, mixing: false)
    }

    func mix(into output: UnsafeMutablePointer<Float>, count: Int) {
        render(into: output, count: count, mixing: true)
    }

    private func render(into output: UnsafeMutablePointer<Float>, count: Int, mixing: Bool) {
        // The CoreAudio render callback must never block behind the producer.
        // Missing one render quantum is preferable to starving the mix clock
        // and muting all received audio until transmission stops.
        guard lock.try() else {
            if !mixing { output.initialize(repeating: 0, count: count) }
            return
        }
        defer { lock.unlock() }
        for index in 0..<count {
            let rendered: Float
            if available > 0 {
                let raw = storage[readIndex]
                readIndex = (readIndex + 1) % storage.count
                available -= 1
                if isMuted {
                    rendered = 0
                    lastOutput = 0
                } else {
                    if wasUnderflowing {
                        wasUnderflowing = false
                        fadeInRemaining = rampSamples
                    }
                    if fadeInRemaining > 0 {
                        let progress = Float(rampSamples - fadeInRemaining + 1) / Float(rampSamples)
                        rendered = raw * progress
                        fadeInRemaining -= 1
                    } else {
                        rendered = raw
                    }
                    lastOutput = rendered
                }
            } else {
                if !wasUnderflowing {
                    wasUnderflowing = true
                    underflowRampRemaining = rampSamples
                }
                if underflowRampRemaining > 0 {
                    let sample = lastOutput * Float(underflowRampRemaining) / Float(rampSamples)
                    rendered = sample
                    lastOutput = sample
                    underflowRampRemaining -= 1
                } else {
                    rendered = 0
                    lastOutput = 0
                }
            }
            if mixing {
                output[index] = min(0.98, max(-0.98, output[index] + rendered))
            } else {
                output[index] = rendered
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
